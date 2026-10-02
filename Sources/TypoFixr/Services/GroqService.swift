import Foundation

protocol TextCorrecting {
    func correctText(_ text: String, apiKey: String, languagePreference: String) async throws -> GroqService.CorrectionResult
}

final class GroqService: TextCorrecting {
    static let shared = GroqService()
    private let transport: any ChatCompletionTransport
    private let chunker = CorrectionChunker()
    private let outputProcessor = CorrectionOutputProcessor()
    private let prompt = CorrectionPrompt()
    private let maxConcurrentChunks = 10
    var promptVersion: String { prompt.promptVersion }

    init(transport: any ChatCompletionTransport = GroqClient()) { self.transport = transport }

    // MARK: - Response Types
    struct CorrectionResult {
        let correctedText: String
        let inputTokens: Int
        let outputTokens: Int
    }

    struct ParsedCompletion {
        let content: String?
        let inputTokens: Int
        let outputTokens: Int
        let finishReason: String?
    }

    struct RequestPolicy {
        let maxCompletionTokens: Int
        let reasoningEffort: String
    }

    struct SentenceChunks {
        let sentences: [String]   // Right-trimmed sentence text for API
        let gaps: [String]        // Separator between sentence[i] and sentence[i+1]
        let leadingGap: String    // Whitespace before first sentence
        let trailingGap: String   // Whitespace after last sentence
    }

    // MARK: - Reassembly Plan (flatten-and-throttle architecture)

    enum ReassemblyPlan {
        case single
        case sentences(SentenceChunks)
        case list(ParsedList)
        case paragraphs(paragraphChunks: SentenceChunks, subPlans: [SubPlan])

        struct SubPlan {
            let chunkRange: Range<Int>   // indices in the flat leaf array
            let kind: SubPlanKind
        }

        enum SubPlanKind {
            case single
            case sentences(SentenceChunks)
            case list(ParsedList)
        }
    }

    struct ParsedList {
        struct Item {
            let prefix: String   // e.g. "- ", "1. ", "• "
            let text: String     // content after prefix
        }
        let items: [Item]
        let gaps: [String]       // gaps[i] = separator between item[i] and item[i+1]
        let leadingGap: String   // whitespace before first item
        let trailingGap: String  // whitespace after last item
    }

    enum APIError: LocalizedError {
        case noApiKey
        case networkError(Error)
        case timeout
        case invalidResponse
        case apiError(String)
        case rateLimited
        case suspiciousOutput(String)
        case outputTooLong
        case aiRefused

        var errorDescription: String? {
            switch self {
            case .noApiKey:
                return "Groq API key not configured. Please add your API key in Settings."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .timeout:
                return "Request timed out after 30s. The API may be slow — please try again."
            case .invalidResponse:
                return "Invalid response from API."
            case .apiError(let message):
                return "API error: \(message)"
            case .rateLimited:
                return "Rate limit exceeded. Please wait a moment and try again."
            case .suspiciousOutput(let reason):
                return "Response blocked for security: \(reason)"
            case .outputTooLong:
                return "Response was unexpectedly long and has been blocked."
            case .aiRefused:
                return "The AI declined to process this text."
            }
        }
    }

    // MARK: - Correct Text
    func correctText(_ text: String, apiKey: String, languagePreference: String) async throws -> CorrectionResult {
        guard !apiKey.isEmpty else {
            throw APIError.noApiKey
        }

        try Task.checkCancellation()
        let (leaves, plan) = chunker.flattenIntoLeafChunks(text)

        // Single leaf — no task group needed
        if leaves.count == 1 {
            return try await correctSingleText(
                text: text,
                apiKey: apiKey,
                languagePreference: languagePreference
            )
        }


        // Single TaskGroup over all leaves with maxConcurrentChunks throttle
        return try await withThrowingTaskGroup(of: (Int, CorrectionResult).self) { group in
            var launched = 0
            var nextToLaunch = 0
            var results = [(Int, CorrectionResult)]()
            results.reserveCapacity(leaves.count)

            // Launch initial batch
            while nextToLaunch < leaves.count && launched < maxConcurrentChunks {
                let idx = nextToLaunch
                let leaf = leaves[idx]
                group.addTask {
                    // Skip empty/whitespace-only leaves
                    guard !leaf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return (idx, CorrectionResult(correctedText: leaf, inputTokens: 0, outputTokens: 0))
                    }
                    let result = try await self.correctSingleText(
                        text: leaf,
                        apiKey: apiKey,
                        languagePreference: languagePreference
                    )
                    return (idx, result)
                }
                launched += 1
                nextToLaunch += 1
            }

            // Collect results and launch remaining
            for try await indexedResult in group {
                try Task.checkCancellation()
                results.append(indexedResult)
                launched -= 1

                if nextToLaunch < leaves.count {
                    let idx = nextToLaunch
                    let leaf = leaves[idx]
                    group.addTask {
                        guard !leaf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return (idx, CorrectionResult(correctedText: leaf, inputTokens: 0, outputTokens: 0))
                        }
                        let result = try await self.correctSingleText(
                            text: leaf,
                            apiKey: apiKey,
                            languagePreference: languagePreference
                        )
                        return (idx, result)
                    }
                    launched += 1
                    nextToLaunch += 1
                }
            }

            // Sort by index and reassemble
            results.sort { $0.0 < $1.0 }
            let correctedTexts = results.map { $0.1.correctedText }
            let totalInput = results.reduce(0) { $0 + $1.1.inputTokens }
            let totalOutput = results.reduce(0) { $0 + $1.1.outputTokens }

            let reassembled = CorrectionChunker.reassembleFromLeafResults(correctedTexts, plan: plan)

            return CorrectionResult(
                correctedText: reassembled,
                inputTokens: totalInput,
                outputTokens: totalOutput
            )
        }
    }

    private func correctSingleText(text: String, apiKey: String, languagePreference: String) async throws -> CorrectionResult {
        let policy = requestPolicy(for: text)
        let requestBody = buildRequestBody(
            text: text,
            languagePreference: languagePreference,
            maxCompletionTokens: policy.maxCompletionTokens,
            reasoningEffort: policy.reasoningEffort
        )
        let parsed = try await transport.performChatCompletionRequest(requestBody: requestBody, apiKey: apiKey)
        return try resolveCorrection(parsed: parsed, originalInput: text)
    }


    func resolveCorrection(parsed: ParsedCompletion, originalInput: String) throws -> CorrectionResult {
        try outputProcessor.resolveCorrection(parsed: parsed, originalInput: originalInput)
    }

    func parseCompletionPayload(_ payload: [String: Any]) throws -> ParsedCompletion {
        try GroqClient().parseCompletionPayload(payload)
    }

    func requestPolicy(for text: String) -> RequestPolicy { prompt.requestPolicy(for: text) }

    func buildRequestBody(text: String, languagePreference: String, maxCompletionTokens: Int? = nil,
                          reasoningEffort: String? = nil) -> [String: Any] {
        prompt.buildRequestBody(text: text, languagePreference: languagePreference,
                                maxCompletionTokens: maxCompletionTokens, reasoningEffort: reasoningEffort)
    }

    func buildInstructions(languagePreference: String) -> String { prompt.buildInstructions(languagePreference: languagePreference) }
}
