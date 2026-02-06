import XCTest
@testable import TypoFixr

final class GroqResponseParsingTests: XCTestCase {
    private let service = GroqService.shared

    func testParseCompletionPayloadReadsStringContent() throws {
        let payload: [String: Any] = [
            "choices": [
                [
                    "finish_reason": "stop",
                    "message": [
                        "content": "Slt, tu fais quoi ce soir ?"
                    ]
                ]
            ],
            "usage": [
                "prompt_tokens": 12,
                "completion_tokens": 8
            ]
        ]

        let parsed = try service.parseCompletionPayload(payload)
        XCTAssertEqual(parsed.content, "Slt, tu fais quoi ce soir ?")
        XCTAssertEqual(parsed.finishReason, "stop")
        XCTAssertEqual(parsed.inputTokens, 12)
        XCTAssertEqual(parsed.outputTokens, 8)
    }

    func testParseCompletionPayloadReadsContentPartArray() throws {
        let payload: [String: Any] = [
            "choices": [
                [
                    "finish_reason": "stop",
                    "message": [
                        "content": [
                            ["type": "text", "text": "Hello"],
                            ["type": "text", "text": " world"]
                        ]
                    ]
                ]
            ],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 3
            ]
        ]

        let parsed = try service.parseCompletionPayload(payload)
        XCTAssertEqual(parsed.content, "Hello world")
        XCTAssertEqual(parsed.finishReason, "stop")
        XCTAssertEqual(parsed.inputTokens, 4)
        XCTAssertEqual(parsed.outputTokens, 3)
    }

    func testRequestPolicyUsesMediumReasoningForLongInput() {
        // >= 300 chars → medium reasoning + overhead 3072 + medium floor 16384
        // max(16384, 4800 + 3072) = 16384
        let policy = service.requestPolicy(for: String(repeating: "a", count: 4_800))
        XCTAssertEqual(policy.reasoningEffort, "medium")
        XCTAssertEqual(policy.maxCompletionTokens, 16_384)
    }

    func testRequestPolicyUsesScaledBudgetFor1300Characters() {
        // >= 300 chars → medium overhead (3072) + medium floor (16384): max(16384, 1300 + 3072) = 16384
        let policy = service.requestPolicy(for: String(repeating: "a", count: 1_300))
        XCTAssertEqual(policy.maxCompletionTokens, 16_384)
    }

    func testResolveCorrectionReturnsSuccessfulCorrection() throws {
        let parsed = GroqService.ParsedCompletion(
            content: "I can't believe this works",
            inputTokens: 10,
            outputTokens: 6,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: "i cant beleive this wrks")
        XCTAssertEqual(result.correctedText, "I can't believe this works")
    }

    func testResolveCorrectionReturnsOriginalOnExplicitNoChangeMarker() throws {
        let original = "This sentence is already clean."
        let parsed = GroqService.ParsedCompletion(
            content: "__NO_CHANGES__",
            inputTokens: 8,
            outputTokens: 2,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, original)
    }

    func testResolveCorrectionReturnsOriginalOnUnchangedOutputWithoutMarker() throws {
        let original = "teh quik brwn fox"
        let parsed = GroqService.ParsedCompletion(
            content: original,
            inputTokens: 8,
            outputTokens: 2,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, original)
    }

    func testResolveCorrectionThrowsOnTruncatedLengthOutput() {
        let original = "teh quik brwn fox jumps over teh lazy dog and runs around teh park"
        let parsed = GroqService.ParsedCompletion(
            content: "the quick brown",
            inputTokens: 20,
            outputTokens: 5,
            finishReason: "length"
        )

        XCTAssertThrowsError(try service.resolveCorrection(parsed: parsed, originalInput: original)) { error in
            guard let apiError = error as? GroqService.APIError,
                  case .apiError(let message) = apiError else {
                XCTFail("Expected apiError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("finish_reason: length"))
        }
    }

    func testResolveCorrectionAcceptsCompleteOutputDespiteLengthFinishReason() throws {
        let original = "teh quik brwn fox jumps over teh lazy dog"
        let parsed = GroqService.ParsedCompletion(
            content: "the quick brown fox jumps over the lazy dog",
            inputTokens: 20,
            outputTokens: 15,
            finishReason: "length"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, "the quick brown fox jumps over the lazy dog")
    }

    func testResolveCorrectionThrowsOnEmptyContent() {
        let parsed = GroqService.ParsedCompletion(
            content: "",
            inputTokens: 8,
            outputTokens: 2,
            finishReason: "stop"
        )

        XCTAssertThrowsError(try service.resolveCorrection(parsed: parsed, originalInput: "teh quik brwn fox")) { error in
            guard let apiError = error as? GroqService.APIError,
                  case .apiError(let message) = apiError else {
                XCTFail("Expected apiError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("empty response"))
        }
    }

    func testResolveCorrectionThrowsOnNilContent() {
        let parsed = GroqService.ParsedCompletion(
            content: nil,
            inputTokens: 8,
            outputTokens: 0,
            finishReason: "stop"
        )

        XCTAssertThrowsError(try service.resolveCorrection(parsed: parsed, originalInput: "teh quik brwn fox")) { error in
            guard let apiError = error as? GroqService.APIError,
                  case .apiError(let message) = apiError else {
                XCTFail("Expected apiError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("empty response"))
        }
    }

    func testResolveCorrectionStripsThinkTagsFromOutput() throws {
        let original = "teh quik brwn fox"
        let parsed = GroqService.ParsedCompletion(
            content: "<think>The user has typos in their text. Let me fix them.</think>the quick brown fox",
            inputTokens: 10,
            outputTokens: 20,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, "the quick brown fox")
    }

    func testResolveCorrectionHandlesUnclosedThinkTag() {
        let original = String(repeating: "a", count: 350)
        let parsed = GroqService.ParsedCompletion(
            content: "<think>The user has typos in their text. Let me analyze each word carefully to determine",
            inputTokens: 30,
            outputTokens: 20,
            finishReason: "length"
        )

        // Unclosed <think> → sanitized to empty → should error
        XCTAssertThrowsError(try service.resolveCorrection(parsed: parsed, originalInput: original)) { error in
            guard let apiError = error as? GroqService.APIError,
                  case .apiError(let message) = apiError else {
                XCTFail("Expected apiError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("finish_reason: length"))
        }
    }

    // MARK: - __NO_CHANGES__ Marker with List Prefix (Bug 1)

    func testResolveCorrectionReturnsOriginalWhenMarkerWithListPrefix() throws {
        let original = "  - URL: "
        let parsed = GroqService.ParsedCompletion(
            content: "__NO_CHANGES__",
            inputTokens: 8,
            outputTokens: 2,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, original)
    }

    func testResolveCorrectionReturnsOriginalWhenMarkerWithAsteriskPrefix() throws {
        let original = "* important note"
        let parsed = GroqService.ParsedCompletion(
            content: "__NO_CHANGES__",
            inputTokens: 8,
            outputTokens: 2,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, original)
    }

    // MARK: - Boundary Quote Restoration (Bug 2)

    func testResolveCorrectionRestoresStrippedLeadingQuote() throws {
        let original = "\"hello wrld\""
        let parsed = GroqService.ParsedCompletion(
            content: "hello world\"",
            inputTokens: 10,
            outputTokens: 6,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, "\"hello world\"")
    }

    func testResolveCorrectionPreservesQuotesWhenModelKeepsThem() throws {
        let original = "\"hello\""
        let parsed = GroqService.ParsedCompletion(
            content: "\"hello\"",
            inputTokens: 8,
            outputTokens: 4,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        // Should NOT double-quote
        XCTAssertEqual(result.correctedText, "\"hello\"")
    }

    func testResolveCorrectionRestoresCurlyQuotes() throws {
        let original = "\u{201C}hello wrld\u{201D}"
        let parsed = GroqService.ParsedCompletion(
            content: "hello world",
            inputTokens: 10,
            outputTokens: 6,
            finishReason: "stop"
        )
        let result = try service.resolveCorrection(parsed: parsed, originalInput: original)
        XCTAssertEqual(result.correctedText, "\u{201C}hello world\u{201D}")
    }

    func testResolveCorrectionThrowsOnEmptyLengthCappedContent() {
        let parsed = GroqService.ParsedCompletion(
            content: "",
            inputTokens: 30,
            outputTokens: 10,
            finishReason: "length"
        )

        XCTAssertThrowsError(try service.resolveCorrection(parsed: parsed, originalInput: String(repeating: "a", count: 4800))) { error in
            guard let apiError = error as? GroqService.APIError,
                  case .apiError(let message) = apiError else {
                XCTFail("Expected apiError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("finish_reason: length"))
        }
    }
}
