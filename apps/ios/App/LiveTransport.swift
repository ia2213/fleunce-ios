import Foundation
import AVFoundation
import FluenceCore

enum ConnectionState: Equatable { case idle, connecting, active, closing, ended, failed }

final class NativeSynthesizer: NSObject, AVSpeechSynthesizerDelegate, Sendable {
    @MainActor private let synth = AVSpeechSynthesizer()
    @MainActor private var finishContinuation: CheckedContinuation<Void, Never>?
    
    @MainActor override init() {
        super.init()
        synth.delegate = self
    }
    
    @MainActor var isSpeaking: Bool { return synth.isSpeaking }
    
    @MainActor func speak(text: String, languageCode: String = "de-DE", rate: Float = 0.50, voiceIdentifier: String = "") {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let bcp = Self.bcp47Code(for: languageCode)
        let utterance = AVSpeechUtterance(string: text)
        
        if !voiceIdentifier.isEmpty, let customVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = customVoice
        } else {
            utterance.voice = Self.bestVoice(for: bcp)
        }
        utterance.rate = min(max(rate, 0.25), 0.75)
        synth.speak(utterance)
    }

    @MainActor func speakAsync(text: String, languageCode: String = "de-DE", rate: Float = 0.50, voiceIdentifier: String = "") async {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finishContinuation?.resume()
        finishContinuation = nil
        
        let bcp = Self.bcp47Code(for: languageCode)
        let utterance = AVSpeechUtterance(string: text)
        
        if !voiceIdentifier.isEmpty, let customVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = customVoice
        } else {
            utterance.voice = Self.bestVoice(for: bcp)
        }
        utterance.rate = min(max(rate, 0.25), 0.75)
        
        await withCheckedContinuation { continuation in
            self.finishContinuation = continuation
            synth.speak(utterance)
        }
    }
    
    @MainActor func stop() {
        finishContinuation?.resume()
        finishContinuation = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.finishContinuation?.resume()
            self?.finishContinuation = nil
        }
    }
    private static func bcp47Code(for id: String) -> String {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("-") { return clean }
        switch clean.lowercased() {
        case "de", "german": return "de-DE"
        case "fr", "french": return "fr-FR"
        case "ro", "romanian": return "ro-RO"
        case "es", "spanish": return "es-ES"
        case "it", "italian": return "it-IT"
        case "pt", "portuguese": return "pt-PT"
        case "nb", "no", "norwegian": return "nb-NO"
        case "zh", "mandarin", "chinese": return "zh-CN"
        case "ja", "japanese": return "ja-JP"
        case "ar", "arabic": return "ar-SA"
        case "en", "english": return "en-US"
        case "nl", "dutch": return "nl-NL"
        case "sv", "swedish": return "sv-SE"
        case "ru", "russian": return "ru-RU"
        case "tr", "turkish": return "tr-TR"
        case "pl", "polish": return "pl-PL"
        case "uk", "ukrainian": return "uk-UA"
        case "el", "greek": return "el-GR"
        case "he", "hebrew": return "he-IL"
        case "hi", "hindi": return "hi-IN"
        case "ko", "korean": return "ko-KR"
        default: return "\(clean)-\(clean.uppercased())"
        }
    }
    private static func bestVoice(for bcp47: String) -> AVSpeechSynthesisVoice? {
        let exactLocale = bcp47.lowercased()
        let langPrefix = String(bcp47.prefix(2)).lowercased()
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        let exactVoices = allVoices.filter { $0.language.lowercased() == exactLocale }
        if let premium = exactVoices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = exactVoices.first(where: { $0.quality == .enhanced }) { return enhanced }
        if let first = exactVoices.first { return first }
        
        let prefixVoices = allVoices.filter { $0.language.lowercased().hasPrefix(langPrefix) }
        if let premium = prefixVoices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = prefixVoices.first(where: { $0.quality == .enhanced }) { return enhanced }
        if let first = prefixVoices.first { return first }
        
        return AVSpeechSynthesisVoice(language: bcp47)
    }
}

@MainActor final class LiveTransport: NSObject {
    var onEvent: (([String: Any]) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    
    private let synthesizer = NativeSynthesizer()
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var meterTask: Task<Void, Never>?
    private var attempt = UUID()
    
    private(set) var started = false
    private(set) var isMuted = false
    private var closing = false
    private var ownsAudioActivation = false
    private var isProcessingSpeech = false
    
    private var api: APIClient?
    private var instructions: String = ""
    private var languageCode: String = "de-DE"
    private var speechRate: Float = 0.50
    private var voiceIdentifier: String = ""
    private var conversationHistory: [[String: String]] = []
    private var preferences = Preferences()
    
    private func cleanModelText(_ raw: String) -> String {
        // Strip backend internal review tags: [FSRS_REVIEW: {"term": "...", "rating": 2}]
        let pattern = #"\s*\[FSRS_REVIEW:.*?\]"#
        return raw.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func connect(api: APIClient, instructions: String, history: [[String: Any]], languageCode: String = "de-DE", speechRate: Float = 0.50, voiceIdentifier: String = "", preferences: Preferences = Preferences()) async throws {
        disconnect()
        closing = false
        self.api = api
        self.preferences = preferences
        self.instructions = instructions
        self.languageCode = languageCode
        self.speechRate = speechRate
        self.voiceIdentifier = voiceIdentifier
        self.conversationHistory = []
        let token = UUID(); attempt = token
        
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw TransportError.microphone }
        try Task.checkCancellation()
        guard attempt == token else { throw CancellationError() }
        
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        ownsAudioActivation = true
        
        let startPrompt = """
        Démarre la séance en tant que Professeur Fluence.
        Consignes impératives :
        - Parle en allemand avec une phrase courte et claire adaptée au niveau de l'élève.
        - INTERDICTION ABSOLUE de répéter 'Wie geht's?' ou 'Wie heißt du?' si l'élève a déjà discuté.
        - Si c'est une continuation ou nouvelle leçon, annonce directement le mini-thème ou la notion du jour et pose ta première consigne ou question d'apprentissage.
        - Reste concis, chaleureux et pédagogique.
        """
        let initialResult = try await api.respond(instructions: instructions, input: startPrompt, model: preferences.groqModel, preferences: preferences)
        guard attempt == token else { throw CancellationError() }
        let sessionID = UUID().uuidString
        onEvent?(["type": "fluence.session.created", "session": ["id": sessionID]])
        started = true
        onEvent?(["type": "session.started", "session": ["id": sessionID]])
        
        if !initialResult.text.isEmpty {
            let cleaned = cleanModelText(initialResult.text)
            if !cleaned.isEmpty {
                conversationHistory.append(["role": "assistant", "content": cleaned])
                onEvent?(["type": "session.output_transcript.delta", "delta": cleaned, "start_ms": 0, "end_ms": 1000, "event_id": UUID().uuidString])
                synthesizer.speak(text: cleaned, languageCode: languageCode, rate: speechRate, voiceIdentifier: voiceIdentifier)
            }
        }
        
        startRecording()
        startAudioLoop()
    }
    
    private func startRecording() {
        guard !closing else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fluence_mic_\(UUID().uuidString).m4a")
        audioURL = url
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
        } catch {
            print("Recorder error:", error)
        }
    }
    
    private func startAudioLoop() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            var speechDetected = false
            var speechDurationCount = 0
            var silenceStart: Date? = nil
            var synthPhase: Double = 0
            var smoothedUserLevel: Double = 0
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.started, !self.isMuted, !self.isProcessingSpeech else { continue }
                
                // When TTS is speaking, emit smooth, gentle, organic vocal envelope
                if self.synthesizer.isSpeaking {
                    speechDetected = false
                    speechDurationCount = 0
                    silenceStart = nil
                    synthPhase += 0.045
                    let wave1 = sin(synthPhase)
                    let wave2 = sin(synthPhase * 1.6 + 0.4)
                    let outputLevel = 0.35 + 0.22 * (0.65 * wave1 + 0.35 * wave2)
                    self.onLevels?(0, max(0.12, min(0.68, outputLevel)))
                    continue
                }
                
                guard let rec = self.recorder, rec.isRecording else { continue }
                
                rec.updateMeters()
                let power = rec.averagePower(forChannel: 0)
                let rawNorm = max(0.0, min(1.0, Double(power + 48) / 38.0))
                let instantaneousLevel = pow(rawNorm, 1.3)
                // Smooth with organic attack/decay envelope
                if instantaneousLevel > smoothedUserLevel {
                    smoothedUserLevel = smoothedUserLevel * 0.55 + instantaneousLevel * 0.45
                } else {
                    smoothedUserLevel = smoothedUserLevel * 0.88 + instantaneousLevel * 0.12
                }
                self.onLevels?(smoothedUserLevel, 0)
                
                // VAD Threshold: -48 dB ensures soft speech, breathing pauses, and natural speech rhythm are captured
                if power > -48 {
                    speechDurationCount += 1
                    if speechDurationCount >= 2 {
                        speechDetected = true
                        silenceStart = nil
                    }
                } else if speechDetected {
                    if silenceStart == nil { silenceStart = Date() }
                    // 1.85s silence required after speech before concluding the turn is finished
                    // This allows natural pauses, grammatical thinking, and complex clauses
                    if let start = silenceStart, Date().timeIntervalSince(start) >= 1.85 {
                        speechDetected = false
                        speechDurationCount = 0
                        silenceStart = nil
                        Task { @MainActor [weak self] in
                            await self?.processSpokenAudio()
                        }
                    }
                } else {
                    speechDurationCount = 0
                }
            }
        }
    }
    
    private func processSpokenAudio() async {
        guard !isProcessingSpeech, let rec = recorder, let url = audioURL, let api else { return }
        guard !synthesizer.isSpeaking else { startRecording(); return }
        
        isProcessingSpeech = true
        rec.stop()
        self.recorder = nil
        
        guard let data = try? Data(contentsOf: url), data.count > 3000 else {
            try? FileManager.default.removeItem(at: url)
            isProcessingSpeech = false
            startRecording()
            return
        }
        
        onLevels?(0.5, 0.5)
        
        do {
            let lang = String(languageCode.prefix(2)).lowercased()
            let userText = try await api.transcribe(audioData: data, language: lang, preferences: preferences).trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: url)
            
            let lower = userText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isSubtitleArtifact = lower.hasPrefix("untertitel von") || lower.hasPrefix("untertitelung") || lower == "amara.org" || lower == "thank you for watching" || lower == "thank you for watching." || lower == "vielen dank fürs zuschauen." || lower == "vielen dank fürs zuschauen" || lower.hasPrefix("subtitles by")
            
            if !userText.isEmpty && userText.count >= 2 && !isSubtitleArtifact && !synthesizer.isSpeaking {
                let startMS = Int(Date().timeIntervalSince1970 * 1000) % 1000000
                onEvent?(["type": "session.input_transcript.delta", "delta": userText, "start_ms": startMS, "end_ms": startMS + 500, "event_id": UUID().uuidString])
                
                conversationHistory.append(["role": "user", "content": userText])
                // Keep only last 5 turns to protect token costs and avoid runaway bills
                let trimmedHistory = Array(conversationHistory.suffix(5))
                let result = try await api.respondHistory(instructions: instructions, history: trimmedHistory, preferences: preferences)
                if !result.text.isEmpty {
                    let cleaned = cleanModelText(result.text)
                    if !cleaned.isEmpty {
                        conversationHistory.append(["role": "assistant", "content": cleaned])
                        let cStartMS = Int(Date().timeIntervalSince1970 * 1000) % 1000000
                        onEvent?(["type": "session.output_transcript.delta", "delta": cleaned, "start_ms": cStartMS, "end_ms": cStartMS + 1000, "event_id": UUID().uuidString])
                        await synthesizer.speakAsync(text: cleaned, languageCode: languageCode, rate: speechRate, voiceIdentifier: voiceIdentifier)
                    }
                }
            }
        } catch {
            print("Speech processing error:", error)
            try? FileManager.default.removeItem(at: url)
        }
        
        isProcessingSpeech = false
        startRecording()
    }
    
    func speak(_ text: String, languageCode: String = "de-DE", rate: Float? = nil, voiceIdentifier: String = "") {
        synthesizer.speak(text: text, languageCode: languageCode, rate: rate ?? speechRate, voiceIdentifier: voiceIdentifier.isEmpty ? self.voiceIdentifier : voiceIdentifier)
    }
    
    @discardableResult func send(_ event: [String: Any]) -> Bool {
        return true
    }
    
    func mute(_ muted: Bool) {
        isMuted = muted
        if muted {
            synthesizer.stop()
            recorder?.pause()
            onLevels?(0, 0)
        } else {
            recorder?.record()
        }
    }
    
    func close() {
        closing = true
        synthesizer.stop()
        recorder?.stop()
    }
    
    func disconnect() {
        attempt = UUID()
        meterTask?.cancel()
        meterTask = nil
        started = false
        closing = true
        synthesizer.stop()
        recorder?.stop()
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
            audioURL = nil
        }
        recorder = nil
        if ownsAudioActivation {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false)
            ownsAudioActivation = false
        }
        onLevels?(0, 0)
    }

    enum TransportError: LocalizedError {
        case microphone, connection, timeout
        var errorDescription: String? {
            switch self {
            case .microphone: "Allow microphone access in iPhone Settings → Fluence to start a conversation."
            case .connection: "The voice connection couldn’t be established. Check your connection and try again."
            case .timeout: "The voice connection took too long. Please try again."
            }
        }
    }
}
