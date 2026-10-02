import Foundation

protocol ChatCompletionTransport {
    func performChatCompletionRequest(requestBody: [String: Any], apiKey: String) async throws -> GroqService.ParsedCompletion
}

struct GroqClient: ChatCompletionTransport {
    typealias ParsedCompletion = GroqService.ParsedCompletion
    typealias APIError = GroqService.APIError
    private static let baseURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    let session: URLSession
    private let timeout: TimeInterval = 30

    init(session: URLSession = .shared) { self.session = session }

    func parseCompletionPayload(_ json: [String: Any]) throws -> ParsedCompletion {
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let content = extractMessageContent(from: message)
        let finishReason = firstChoice["finish_reason"] as? String

        var inputTokens = 0
        var outputTokens = 0
        if let usage = json["usage"] as? [String: Any] {
            inputTokens = usage["prompt_tokens"] as? Int ?? 0
            outputTokens = usage["completion_tokens"] as? Int ?? 0
        }

        return ParsedCompletion(
            content: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            finishReason: finishReason
        )
    }

    private func extractMessageContent(from message: [String: Any]) -> String? {
        if let stringContent = message["content"] as? String {
            return stringContent
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            let textParts = contentParts.compactMap { part -> String? in
                if let text = part["text"] as? String {
                    return text
                }
                if let text = part["content"] as? String {
                    return text
                }
                return nil
            }
            return textParts.joined()
        }

        if let contentParts = message["content"] as? [Any] {
            let textParts = contentParts.compactMap { part -> String? in
                if let text = part as? String {
                    return text
                }
                if let dictionary = part as? [String: Any] {
                    if let text = dictionary["text"] as? String {
                        return text
                    }
                    if let text = dictionary["content"] as? String {
                        return text
                    }
                }
                return nil
            }
            return textParts.joined()
        }

        return nil
    }

    func performChatCompletionRequest(requestBody: [String: Any], apiKey: String) async throws -> ParsedCompletion {
        var request = URLRequest(url: Self.baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout


        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw APIError.timeout
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }

        // Handle other errors
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw APIError.apiError(message)
            }
            throw APIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse Chat Completions API format
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let parsedCompletion = try parseCompletionPayload(json)


        return parsedCompletion
    }

}
