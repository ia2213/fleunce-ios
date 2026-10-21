import Foundation
import UIKit
import Vision
import FluenceCore

@MainActor
final class VisionOCRManager {
    static let shared = VisionOCRManager()
    
    // MARK: - Local Apple Vision OCR (Offline & Fast)
    func extractTextWithVision(from image: UIImage, targetLanguageCode: String = "de") async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                // Sort observations vertically from top to bottom
                let sorted = observations.sorted { (a, b) -> Bool in
                    let aY = a.boundingBox.origin.y
                    let bY = b.boundingBox.origin.y
                    if abs(aY - bY) > 0.03 {
                        return aY > bY // Vision coordinates have (0,0) at bottom-left
                    }
                    return a.boundingBox.origin.x < b.boundingBox.origin.x
                }
                
                var lines: [String] = []
                for obs in sorted {
                    if let candidate = obs.topCandidates(1).first {
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            lines.append(text)
                        }
                    }
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            // Set candidate recognition languages
            var candidateLanguages = ["fr-FR", "de-DE", "en-US", "es-ES", "it-IT"]
            if targetLanguageCode == "de" {
                candidateLanguages.insert("de-DE", at: 0)
            } else if targetLanguageCode == "es" {
                candidateLanguages.insert("es-ES", at: 0)
            } else if targetLanguageCode == "it" {
                candidateLanguages.insert("it-IT", at: 0)
            }
            request.recognitionLanguages = candidateLanguages
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: Self.cgImageOrientation(from: image.imageOrientation), options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Multimodal Gemini Vision (Single & Multi-Page Support)
    func extractAndParseWithGemini(
        images: [UIImage],
        apiClient: APIClient,
        preferences: Preferences,
        targetLanguage: String = "German"
    ) async throws -> AssimilLesson {
        guard !images.isEmpty else { throw OCRError.invalidImage }
        
        let key = preferences.googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            // Fallback to local OCR on all images + LLM structure
            var combinedText = ""
            for (idx, img) in images.enumerated() {
                let text = try await extractTextWithVision(from: img, targetLanguageCode: preferences.learningLanguageID)
                combinedText += "--- Page \(idx + 1) ---\n" + text + "\n\n"
            }
            return try await structureRawTextIntoLesson(rawText: combinedText, apiClient: apiClient, preferences: preferences, targetLanguage: targetLanguage)
        }
        
        // Multi-image base64 parts for Gemini
        var contentParts: [[String: Any]] = [
            ["type": "text", "text": AssimilTeacherPolicy.ocrStructuringPrompt(targetLanguage: targetLanguage) + "\n\nNote : Il y a \(images.count) photo(s) consécutives de la leçon Assimil (par exemple page gauche de dialogue/phonétique et page droite de traduction/grammaire/exercices). Assemble et fusionne toutes les pages en une seule leçon cohérente et structurée."]
        ]
        
        for img in images {
            let resized = img.resized(maxDimension: 1500)
            if let jpegData = resized.jpegData(compressionQuality: 0.8) {
                let base64Image = jpegData.base64EncodedString()
                let dataURI = "data:image/jpeg;base64,\(base64Image)"
                contentParts.append(["type": "image_url", "image_url": ["url": dataURI]])
            }
        }
        
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        let model = preferences.geminiModel.isEmpty ? "gemini-2.0-flash" : preferences.geminiModel
        
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": contentParts
            ]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 4000,
            "response_format": ["type": "json_object"]
        ]
        
        do {
            let json = try await apiClient.postURL(endpoint, body: body, token: key)
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw OCRError.parsingFailed
            }
            
            return try decodeLessonJSON(content, rawTextFallback: "")
        } catch {
            // Fallback to Vision OCR + Text LLM
            var combinedText = ""
            for (idx, img) in images.enumerated() {
                let text = (try? await extractTextWithVision(from: img, targetLanguageCode: preferences.learningLanguageID)) ?? ""
                combinedText += "--- Page \(idx + 1) ---\n" + text + "\n\n"
            }
            return try await structureRawTextIntoLesson(rawText: combinedText, apiClient: apiClient, preferences: preferences, targetLanguage: targetLanguage)
        }
    }

    // Convenience method for single image
    func extractAndParseWithGemini(
        image: UIImage,
        apiClient: APIClient,
        preferences: Preferences,
        targetLanguage: String = "German"
    ) async throws -> AssimilLesson {
        return try await extractAndParseWithGemini(images: [image], apiClient: apiClient, preferences: preferences, targetLanguage: targetLanguage)
    }
    
    // MARK: - Structure Raw OCR Text into Assimil Lesson
    func structureRawTextIntoLesson(
        rawText: String,
        apiClient: APIClient,
        preferences: Preferences,
        targetLanguage: String = "German"
    ) async throws -> AssimilLesson {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRError.noTextFound
        }
        
        let instructions = AssimilTeacherPolicy.ocrStructuringPrompt(targetLanguage: targetLanguage)
        let history = [
            ["role": "user", "content": "Voici le texte extrait de la leçon Assimil :\n\n\(rawText)"]
        ]
        
        do {
            let result = try await apiClient.respondHistory(instructions: instructions, history: history, preferences: preferences)
            return try decodeLessonJSON(result.text, rawTextFallback: rawText)
        } catch {
            // Fallback basic lesson when LLM call fails
            return createBasicLessonFromText(rawText: rawText, targetLanguage: targetLanguage)
        }
    }
    
    // MARK: - JSON Decoding Helpers
    private func decodeLessonJSON(_ jsonString: String, rawTextFallback: String) throws -> AssimilLesson {
        var cleanJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanJSON.hasPrefix("```json") {
            cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "")
        }
        if cleanJSON.hasPrefix("```") {
            cleanJSON = cleanJSON.replacingOccurrences(of: "```", with: "")
        }
        cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return createBasicLessonFromText(rawText: rawTextFallback.isEmpty ? jsonString : rawTextFallback, targetLanguage: "German")
        }
        
        let lessonNumber = dict["lessonNumber"] as? Int
        let title = dict["title"] as? String ?? "Leçon Assimil"
        
        var dialogueLines: [AssimilLine] = []
        if let rawDialogue = dict["dialogue"] as? [[String: Any]] {
            for (i, item) in rawDialogue.enumerated() {
                let lineIdx = item["lineIndex"] as? Int ?? (i + 1)
                let speaker = item["speaker"] as? String
                let targetText = item["targetText"] as? String ?? ""
                let phonetic = item["phonetic"] as? String
                let nativeTranslation = item["nativeTranslation"] as? String ?? ""
                let notes = item["notes"] as? String
                if !targetText.isEmpty {
                    dialogueLines.append(AssimilLine(
                        lineIndex: lineIdx,
                        speaker: speaker,
                        targetText: targetText,
                        phonetic: phonetic,
                        nativeTranslation: nativeTranslation,
                        notes: notes
                    ))
                }
            }
        }
        
        let grammarNotes = dict["grammarNotes"] as? [String] ?? []
        
        var exercises: [AssimilExercise] = []
        if let rawExercises = dict["exercises"] as? [[String: Any]] {
            for exItem in rawExercises {
                let exTitle = exItem["title"] as? String ?? "Exercice"
                let instructions = exItem["instructions"] as? String ?? ""
                var items: [AssimilExerciseItem] = []
                if let rawItems = exItem["items"] as? [[String: Any]] {
                    for (j, item) in rawItems.enumerated() {
                        let itemIdx = item["itemIndex"] as? Int ?? (j + 1)
                        let prompt = item["prompt"] as? String ?? ""
                        let hint = item["hint"] as? String
                        let expected = item["expectedAnswer"] as? String ?? ""
                        let explanation = item["explanation"] as? String
                        if !prompt.isEmpty {
                            items.append(AssimilExerciseItem(
                                itemIndex: itemIdx,
                                prompt: prompt,
                                hint: hint,
                                expectedAnswer: expected,
                                explanation: explanation
                            ))
                        }
                    }
                }
                exercises.append(AssimilExercise(title: exTitle, instructions: instructions, items: items))
            }
        }
        
        return AssimilLesson(
            lessonNumber: lessonNumber,
            title: title,
            targetLanguageID: "de",
            nativeLanguageID: "fr",
            rawExtractedText: rawTextFallback,
            dialogue: dialogueLines,
            grammarNotes: grammarNotes,
            exercises: exercises
        )
    }
    
    private func createBasicLessonFromText(rawText: String, targetLanguage: String) -> AssimilLesson {
        let lines = rawText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var dialogueLines: [AssimilLine] = []
        for (i, line) in lines.prefix(15).enumerated() {
            dialogueLines.append(AssimilLine(
                lineIndex: i + 1,
                targetText: line,
                nativeTranslation: "À traduire avec Fluence"
            ))
        }
        
        return AssimilLesson(
            lessonNumber: 1,
            title: "Leçon Assimil Scannée",
            targetLanguageID: "de",
            nativeLanguageID: "fr",
            rawExtractedText: rawText,
            dialogue: dialogueLines,
            grammarNotes: ["Texte scanné prêt pour l'étude avec le professeur Fluence."],
            exercises: []
        )
    }
    
    private static func cgImageOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - UIImage Helper Extension
extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

public enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound
    case parsingFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "L'image sélectionnée est invalide ou illisible."
        case .noTextFound: return "Aucun texte n'a pu être extrait de cette image."
        case .parsingFailed: return "L'analyse de la leçon a échoué. Veuillez réessayer."
        }
    }
}
