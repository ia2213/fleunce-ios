import Foundation
import FluenceCore

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct APIUsage { var input = 0; var output = 0; var searches = 0 }
struct APIResult { var text: String; var sources: [SourceLink]; var usage: APIUsage }

@MainActor final class APIClient {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    
    func postURL(_ urlString: String, body: [String: Any], token: String = "", customHeaders: [String: String] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        for (k, v) in customHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderFailure(status: http.statusCode, body: data, reference: http.value(forHTTPHeaderField: "x-request-id") ?? http.value(forHTTPHeaderField: "x-goog-request-id"))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidResponse }
        return json
    }

    private func sanitizeModel(_ model: String) -> String {
        let clean = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean.contains("llama") { return "qwen/qwen3.8-27b" }
        if clean.lowercased().hasPrefix("ilama") { return "qwen/qwen3.8-27b" }
        return clean
    }

    func fetchAvailableModels() async throws -> [String] {
        let key = KeychainHelper.shared.read(for: .groq) ?? KeychainHelper.shared.read(for: .owner) ?? ""
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let endpoint = URL(string: "https://api.groq.com/openai/v1/models")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }.filter { !$0.contains("whisper") && !$0.contains("guard") && !$0.contains("prompt") }
    }

    func respond(instructions: String, input: String, schema: [String: Any]? = nil, search: Bool = false, model: String = "", preferences: Preferences = Preferences()) async throws -> APIResult {
        try checkAIConsent(preferences: preferences)
        return try await respondHistory(
            instructions: instructions,
            history: [["role": "user", "content": input]],
            model: model,
            preferences: preferences
        )
    }

    // MARK: - 1. Groq Cloud (Ultra-Rapide)
    func executeGroq(instructions: String, history: [[String: String]], model: String = "", prefs: Preferences = Preferences()) async throws -> APIResult {
        let key = prefs.groqAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .groq) ?? KeychainHelper.shared.read(for: .owner) ?? "") : prefs.groqAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://api.groq.com/openai/v1/chat/completions"
        let selectedModel = model.isEmpty ? prefs.groqModel : sanitizeModel(model)
        
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        
        var body: [String: Any] = [
            "model": selectedModel,
            "messages": messages,
            "max_tokens": 1400
        ]
        let json: [String: Any]
        do {
            json = try await postURL(endpoint, body: body, token: key)
        } catch let failure as ProviderFailure where [400, 403, 404, 429, 500, 502, 503].contains(failure.status) {
            let available = (try? await fetchAvailableModels()) ?? []
            if let fallbackModel = available.first(where: { $0 != selectedModel }) {
                body["model"] = fallbackModel
                json = try await postURL(endpoint, body: body, token: key)
            } else if selectedModel != "qwen/qwen3.8-27b" {
                body["model"] = "qwen/qwen3.8-27b"
                json = try await postURL(endpoint, body: body, token: key)
            } else {
                throw failure
            }
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        var usage = APIUsage()
        if let u = json["usage"] as? [String: Any] {
            usage.input = u["prompt_tokens"] as? Int ?? 0
            usage.output = u["completion_tokens"] as? Int ?? 0
        }
        guard !text.isEmpty else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: usage)
    }

    // MARK: - 2. OpenAI (ChatGPT / GPT-4o / o1 / o3-mini)
    func executeOpenAI(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let key = prefs.openaiAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .openai) ?? "") : prefs.openaiAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://api.openai.com/v1/chat/completions"
        let model = prefs.openaiModel.isEmpty ? "gpt-4o-mini" : prefs.openaiModel
        
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 3. Anthropic Claude (Claude 3.5 Sonnet / Haiku / Opus)
    func executeAnthropic(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let key = prefs.anthropicAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .anthropic) ?? "") : prefs.anthropicAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://api.anthropic.com/v1/messages"
        let model = prefs.anthropicModel.isEmpty ? "claude-3-5-sonnet-20241022" : prefs.anthropicModel
        
        var messages: [[String: Any]] = []
        for msg in history {
            let role = (msg["role"] ?? "user") == "assistant" ? "assistant" : "user"
            messages.append(["role": role, "content": msg["content"] ?? ""])
        }
        if messages.isEmpty {
            messages.append(["role": "user", "content": "Hallo!"])
        }
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1400,
            "system": instructions,
            "messages": messages
        ]
        let headers: [String: String] = [
            "x-api-key": key,
            "anthropic-version": "2023-06-01"
        ]
        let json = try await postURL(endpoint, body: body, token: "", customHeaders: headers)
        guard let contentList = json["content"] as? [[String: Any]],
              let firstContent = contentList.first,
              let text = firstContent["text"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 4. Google Gemini (2.0 Flash / Pro)
    func executeGemini(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let key = prefs.googleAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .google) ?? "") : prefs.googleAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        let model = prefs.geminiModel.isEmpty ? "gemini-2.0-flash" : prefs.geminiModel
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 5. DeepSeek (DeepSeek V3 / R1)
    func executeDeepSeek(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let key = prefs.deepseekAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .deepseek) ?? "") : prefs.deepseekAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://api.deepseek.com/chat/completions"
        let model = prefs.deepseekModel.isEmpty ? "deepseek-chat" : prefs.deepseekModel
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 6. Mistral AI (Mistral Large / Small / Codestral)
    func executeMistral(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let key = prefs.mistralAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .mistral) ?? "") : prefs.mistralAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://api.mistral.ai/v1/chat/completions"
        let model = prefs.mistralModel.isEmpty ? "mistral-small-latest" : prefs.mistralModel
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 7. OpenRouter (100+ Modèles)
    func executeOpenRouter(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let key = prefs.openrouterAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .openrouter) ?? "") : prefs.openrouterAPIKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.missingKey }
        let endpoint = "https://openrouter.ai/api/v1/chat/completions"
        let model = prefs.openrouterModel.isEmpty ? "meta-llama/llama-3.3-70b-instruct:free" : prefs.openrouterModel
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 8. Custom OpenAI-compatible Server (Ollama / LM Studio / vLLM)
    func executeCustom(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let endpoint = prefs.customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { throw APIError.missingKey }
        let key = prefs.customAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .custom) ?? "") : prefs.customAPIKey
        let model = prefs.customModel.isEmpty ? "llama3" : prefs.customModel
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - 9. Hermes VPS Personnel
    func executeHermesVPS(instructions: String, history: [[String: String]], prefs: Preferences) async throws -> APIResult {
        let endpoint = prefs.vpsEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { throw APIError.missingKey }
        let key = prefs.vpsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = prefs.vpsModel.isEmpty ? "auto/best-coding" : prefs.vpsModel
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for msg in history {
            messages.append(["role": msg["role"] ?? "user", "content": msg["content"] ?? ""])
        }
        let body: [String: Any] = ["model": model, "messages": messages, "max_tokens": 1400]
        let json = try await postURL(endpoint, body: body, token: key)
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else { throw APIError.incomplete }
        return APIResult(text: text, sources: [], usage: APIUsage())
    }

    // MARK: - Smart Failover Dispatcher
    func respondHistory(instructions: String, history: [[String: String]], model: String = "", preferences: Preferences = Preferences()) async throws -> APIResult {
        try checkAIConsent(preferences: preferences)
        let mode = preferences.providerID.lowercased()
        
        let allProviders = ["groq", "openai", "anthropic", "google", "deepseek", "mistral", "openrouter", "hermes_vps", "custom"]
        let providersToTry: [String] = {
            if mode != "auto" && allProviders.contains(mode) {
                var list = [mode]
                list.append(contentsOf: allProviders.filter { $0 != mode })
                return list
            }
            return allProviders
        }()
        
        var lastError: Error? = nil
        for provider in providersToTry {
            do {
                switch provider {
                case "groq":
                    return try await executeGroq(instructions: instructions, history: history, model: model, prefs: preferences)
                case "openai":
                    return try await executeOpenAI(instructions: instructions, history: history, prefs: preferences)
                case "anthropic":
                    return try await executeAnthropic(instructions: instructions, history: history, prefs: preferences)
                case "google":
                    return try await executeGemini(instructions: instructions, history: history, prefs: preferences)
                case "deepseek":
                    return try await executeDeepSeek(instructions: instructions, history: history, prefs: preferences)
                case "mistral":
                    return try await executeMistral(instructions: instructions, history: history, prefs: preferences)
                case "openrouter":
                    return try await executeOpenRouter(instructions: instructions, history: history, prefs: preferences)
                case "custom":
                    return try await executeCustom(instructions: instructions, history: history, prefs: preferences)
                case "hermes_vps":
                    return try await executeHermesVPS(instructions: instructions, history: history, prefs: preferences)
                default:
                    break
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? APIError.incomplete
    }

    func transcribe(audioData: Data, language: String = "en", preferences: Preferences = Preferences()) async throws -> String {
        try checkAIConsent(preferences: preferences)

        // ZDR / COPPA-RGPD-K : aucune voix d'enfant ne quitte l'appareil
        if preferences.isKidsModeActive {
            throw APIError.kidsModeAudioBlocked
        }

        let groqKey = preferences.groqAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .groq) ?? KeychainHelper.shared.read(for: .owner) ?? "") : preferences.groqAPIKey
        let openaiKey = preferences.openaiAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .openai) ?? "") : preferences.openaiAPIKey
        let geminiKey = preferences.googleAPIKey.isEmpty ? (KeychainHelper.shared.read(for: .google) ?? "") : preferences.googleAPIKey
        
        // 1. Try Groq Whisper Turbo
        if !groqKey.isEmpty {
            do {
                return try await transcribeGroq(audioData: audioData, language: language, key: groqKey)
            } catch {
                print("Groq Whisper transcription failed: \(error). Trying fallback...")
            }
        }
        
        // 2. Try OpenAI Whisper
        if !openaiKey.isEmpty {
            do {
                return try await transcribeOpenAI(audioData: audioData, language: language, key: openaiKey)
            } catch {
                print("OpenAI Whisper transcription failed: \(error). Trying fallback...")
            }
        }
        
        // 3. Fallback to Gemini 2.0 Flash Audio Transcription
        if !geminiKey.isEmpty {
            do {
                return try await transcribeGemini(audioData: audioData, key: geminiKey)
            } catch {
                print("Gemini transcription failed: \(error)")
            }
        }
        
        if groqKey.isEmpty && openaiKey.isEmpty && geminiKey.isEmpty {
            throw APIError.missingKey
        }
        throw APIError.incomplete
    }
    
    private func transcribeOpenAI(audioData: Data, language: String, key: String) async throws -> String {
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")

        var body = Data()
        let crlf = Data([0x0D, 0x0A])
        func addField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)".utf8))
            body.append(crlf)
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"".utf8))
            body.append(crlf)
            body.append(crlf)
            body.append(Data(value.utf8))
            body.append(crlf)
        }
        addField("model", "whisper-1")
        addField("response_format", "json")
        if !language.isEmpty { addField("language", language) }

        body.append(Data("--\(boundary)".utf8))
        body.append(crlf)
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"".utf8))
        body.append(crlf)
        body.append(Data("Content-Type: audio/m4a".utf8))
        body.append(crlf)
        body.append(crlf)
        body.append(audioData)
        body.append(crlf)
        body.append(Data("--\(boundary)--".utf8))
        body.append(crlf)

        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else { throw APIError.incomplete }
        return text
    }

    private func transcribeGroq(audioData: Data, language: String, key: String) async throws -> String {
        let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")

        var body = Data()
        let crlf = Data([0x0D, 0x0A])
        func addField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)".utf8))
            body.append(crlf)
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"".utf8))
            body.append(crlf)
            body.append(crlf)
            body.append(Data(value.utf8))
            body.append(crlf)
        }
        addField("model", "whisper-large-v3-turbo")
        addField("response_format", "json")
        if !language.isEmpty { addField("language", language) }

        body.append(Data("--\(boundary)".utf8))
        body.append(crlf)
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"".utf8))
        body.append(crlf)
        body.append(Data("Content-Type: audio/m4a".utf8))
        body.append(crlf)
        body.append(crlf)
        body.append(audioData)
        body.append(crlf)
        body.append(Data("--\(boundary)--".utf8))
        body.append(crlf)

        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else { throw APIError.incomplete }
        return text
    }

    private func transcribeGemini(audioData: Data, key: String) async throws -> String {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(key)"
        let base64Audio = audioData.base64EncodedString()
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": "Transcribe the spoken words in this audio exactly as uttered. Return ONLY the transcribed text, nothing else."],
                    ["inline_data": ["mime_type": "audio/m4a", "data": base64Audio]]
                ]
            ]],
            "generationConfig": ["temperature": 0.0]
        ]
        let json = try await postURL(endpoint, body: body)
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else { throw APIError.incomplete }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkAIConsent(preferences: Preferences) throws {
        guard preferences.aiConsentVersion == AIProcessingConsent.version else {
            throw APIError.consentRequired
        }
    }

    static func object(_ fields: [String: Any]) -> [String: Any] { ["type": "OBJECT", "properties": fields, "required": fields.keys.sorted()] }
    static let string: [String: Any] = ["type": "STRING"]
    static func assessmentSchema(language: LanguageModule) -> [String: Any] { object([
        "outcome": ["type": "STRING", "enum": ["success", "partial", "breakdown", "uncertain"]],
        "suggestedLevel": ["type": "INTEGER"], "nextGoal": string, "capability": string,
        "words": ["type": "ARRAY", "items": object([
            "lemma": string, "meaning": string, "form": string, "quote": string, "language": ["type": "STRING", "enum": Array(Set([language.id, "en", "mixed", "uncertain"])).sorted()],
            "kind": ["type": "STRING", "enum": ["exposure", "understanding", "assisted", "independent", "lapse"]],
            "confidence": ["type": "NUMBER"], "sourceIDs": ["type": "ARRAY", "items": string]
        ])]
    ]) }
    enum APIError: LocalizedError {
        case missingKey, invalidResponse, incomplete, refused, http(Int), consentRequired, kidsModeAudioBlocked
        var errorDescription: String? {
            switch self {
            case .missingKey: "Veuillez entrer votre clé API dans les Réglages pour le fournisseur sélectionné."
            case .invalidResponse, .incomplete: "Le fournisseur d'IA a retourné une réponse incomplète. Veuillez réessayer."
            case .refused: "Fluence n'a pas pu compléter cette requête. Essayez un autre sujet."
            case .http(401), .http(403): "Votre clé API ou endpoint n'a pas été accepté (Erreur HTTP 401/403)."
            case .http(404): "Le modèle sélectionné n'a pas été trouvé chez le fournisseur (Erreur HTTP 404)."
            case .http(429): "La limite de requêtes (Rate Limit) de l'API a été atteinte. Réessayez dans un instant."
            case .http(let status): "Le service d'IA a rencontré une erreur (HTTP \\(status))."
            case .consentRequired: "Vous devez accepter le consentement IA avant d'utiliser les fonctionnalités de traitement par IA."
            case .kidsModeAudioBlocked: "Mode Enfant actif : la transcription vocale cloud est désactivée pour protéger la voix de l'enfant (ZDR/COPPA). Utilisez l'instructeur d'accent sur l'appareil."
            }
        }
    }
}
