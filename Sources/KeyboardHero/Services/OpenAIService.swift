import Foundation

class OpenAIService {
    static let shared = OpenAIService()
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"
    private let timeout: TimeInterval = 5.0
    
    private init() {}
    
    // MARK: - Response Types
    struct CorrectionResult {
        let correctedText: String
        let inputTokens: Int
        let outputTokens: Int
    }
    
    enum OpenAIError: LocalizedError {
        case noApiKey
        case networkError(Error)
        case timeout
        case invalidResponse
        case apiError(String)
        case emptyResponse
        case rateLimited
        
        var errorDescription: String? {
            switch self {
            case .noApiKey:
                return "OpenAI API key not configured. Please add your API key in Settings."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .timeout:
                return "Request timed out. Please try again."
            case .invalidResponse:
                return "Invalid response from API."
            case .apiError(let message):
                return "API error: \(message)"
            case .emptyResponse:
                return "Received empty response from API."
            case .rateLimited:
                return "Rate limit exceeded. Please wait a moment and try again."
            }
        }
    }
    
    // MARK: - Correct Text
    func correctText(_ text: String, apiKey: String, languagePreference: String) async throws -> CorrectionResult {
        guard !apiKey.isEmpty else {
            throw OpenAIError.noApiKey
        }
        
        let systemPrompt = buildSystemPrompt(languagePreference: languagePreference)
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": min(text.count * 2, 1000), // Reasonable limit based on input
            "temperature": 0.1 // Low temperature for consistent corrections
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw OpenAIError.rateLimited
        }
        
        // Handle other errors
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        
        let correctedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if correctedText.isEmpty {
            throw OpenAIError.emptyResponse
        }
        
        // Get token usage
        var inputTokens = 0
        var outputTokens = 0
        if let usage = json["usage"] as? [String: Any] {
            inputTokens = usage["prompt_tokens"] as? Int ?? 0
            outputTokens = usage["completion_tokens"] as? Int ?? 0
        }
        
        return CorrectionResult(
            correctedText: correctedText,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
    
    // MARK: - System Prompt
    private func buildSystemPrompt(languagePreference: String) -> String {
        var prompt = """
        You are a typo and grammar fixer. Your job is to fix spelling mistakes, typos, and basic grammar errors in the user's text.

        IMPORTANT RULES:
        1. Only fix clear errors (typos, misspellings, obvious grammar mistakes)
        2. Preserve the user's exact tone, style, and word choices
        3. Do NOT rephrase, improve, or change the meaning
        4. Keep informal language informal (don't formalize casual text)
        5. Preserve intentional stylistic choices (like ALL CAPS for emphasis)
        6. Keep abbreviations as-is (don't expand "msg" to "message")
        7. Preserve all emojis, special characters, and formatting
        8. Preserve line breaks and paragraph structure
        9. Return ONLY the corrected text with no explanation, commentary, or quotes
        """
        
        if languagePreference == "auto" {
            prompt += "\n10. Preserve the original language of the text - do not translate"
        } else {
            prompt += "\n10. Ensure the output is in \(languagePreference)"
        }
        
        return prompt
    }
}
