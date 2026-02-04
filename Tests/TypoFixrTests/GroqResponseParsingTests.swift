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

    func testRequestPolicyUsesLowInitialEffortAndMediumRetryEffort() {
        let policy = service.requestPolicy(for: String(repeating: "a", count: 4_800))
        XCTAssertEqual(policy.reasoningEffort, "low")
        XCTAssertEqual(policy.retryReasoningEffort, "medium")
        XCTAssertTrue(policy.allowLengthRetry)
        XCTAssertEqual(policy.initialMaxCompletionTokens, 8_192)
        XCTAssertEqual(policy.retryMaxCompletionTokens, 12_288)
    }

    func testRequestPolicyKeepsStandardTierFormulaFor1300Characters() {
        let policy = service.requestPolicy(for: String(repeating: "a", count: 1_300))
        XCTAssertEqual(policy.initialMaxCompletionTokens, 1_162)
        XCTAssertEqual(policy.retryMaxCompletionTokens, 2_324)
    }

    func testResolveCorrectionWithRetryRetriesOnUnchangedOutputWithoutMarker() async throws {
        var observedMaxCompletionTokens: [Int] = []
        var observedVerificationPass: [Bool] = []
        let text = "i cant beleive this wrks"
        let policy = service.requestPolicy(for: text)

        let result = try await service.resolveCorrectionWithRetry(
            text: text,
            requestPolicy: policy
        ) { maxCompletionTokens, _, verificationPass in
            observedMaxCompletionTokens.append(maxCompletionTokens)
            observedVerificationPass.append(verificationPass)
            if observedMaxCompletionTokens.count == 1 {
                return GroqService.ParsedCompletion(content: text, inputTokens: 10, outputTokens: 3, finishReason: "stop")
            }
            return GroqService.ParsedCompletion(content: "I can't believe this works", inputTokens: 10, outputTokens: 6, finishReason: "stop")
        }

        XCTAssertEqual(observedMaxCompletionTokens.count, 2)
        XCTAssertEqual(observedMaxCompletionTokens[0], policy.initialMaxCompletionTokens)
        XCTAssertEqual(observedMaxCompletionTokens[1], policy.retryMaxCompletionTokens)
        XCTAssertEqual(observedVerificationPass, [false, true])
        XCTAssertEqual(result.correctedText, "I can't believe this works")
    }

    func testResolveCorrectionWithRetryAcceptsExplicitNoChangeMarker() async throws {
        let text = "This sentence is already clean."
        let policy = service.requestPolicy(for: text)

        let result = try await service.resolveCorrectionWithRetry(
            text: text,
            requestPolicy: policy
        ) { _, _, _ in
            GroqService.ParsedCompletion(content: "__NO_CHANGES__", inputTokens: 8, outputTokens: 2, finishReason: "stop")
        }

        XCTAssertEqual(result.correctedText, text)
    }

    func testResolveCorrectionWithRetryThrowsReliabilityErrorAfterSecondUnchangedOutput() async {
        var observedMaxCompletionTokens: [Int] = []
        let text = "teh quik brwn fox"
        let policy = service.requestPolicy(for: text)

        do {
            _ = try await service.resolveCorrectionWithRetry(
                text: text,
                requestPolicy: policy
            ) { maxCompletionTokens, _, _ in
                observedMaxCompletionTokens.append(maxCompletionTokens)
                return GroqService.ParsedCompletion(content: text, inputTokens: 8, outputTokens: 2, finishReason: "stop")
            }
            XCTFail("Expected unreliableNoChange when both attempts return unchanged text without marker")
        } catch let error as GroqService.APIError {
            switch error {
            case .unreliableNoChange:
                XCTAssertEqual(observedMaxCompletionTokens.count, 2)
            default:
                XCTFail("Expected unreliableNoChange, got \(error)")
            }
        } catch {
            XCTFail("Expected GroqService.APIError, got \(error)")
        }
    }

    func testResolveCorrectionWithRetryRetriesOnLengthAndCapsAtOneRetry() async {
        var observedMaxCompletionTokens: [Int] = []
        let text = String(repeating: "a", count: 4800)
        let policy = service.requestPolicy(for: text)

        do {
            _ = try await service.resolveCorrectionWithRetry(
                text: text,
                requestPolicy: policy
            ) { maxCompletionTokens, _, _ in
                observedMaxCompletionTokens.append(maxCompletionTokens)
                return GroqService.ParsedCompletion(content: "", inputTokens: 30, outputTokens: 10, finishReason: "length")
            }
            XCTFail("Expected apiError when both attempts finish with length")
        } catch let error as GroqService.APIError {
            switch error {
            case .apiError(let message):
                XCTAssertEqual(observedMaxCompletionTokens.count, 2)
                XCTAssertEqual(observedMaxCompletionTokens, [8_192, 12_288])
                XCTAssertTrue(message.contains("exceeded output budget after retry"))
                XCTAssertTrue(message.contains("finish_reason: length"))
            default:
                XCTFail("Expected apiError, got \(error)")
            }
        } catch {
            XCTFail("Expected GroqService.APIError, got \(error)")
        }
    }

    func testResolveCorrectionAcceptsCompleteOutputDespiteLengthFinishReason() async throws {
        let text = "teh quik brwn fox jumps over teh lazy dog"
        let policy = service.requestPolicy(for: text)

        let result = try await service.resolveCorrectionWithRetry(
            text: text,
            requestPolicy: policy
        ) { _, _, _ in
            // Model returns complete correction but finish_reason is "length"
            // because reasoning tokens consumed the budget
            GroqService.ParsedCompletion(
                content: "the quick brown fox jumps over the lazy dog",
                inputTokens: 20,
                outputTokens: 15,
                finishReason: "length"
            )
        }

        XCTAssertEqual(result.correctedText, "the quick brown fox jumps over the lazy dog")
    }

    func testResolveCorrectionRetriesOnTruncatedLengthOutput() async throws {
        var callCount = 0
        let text = "teh quik brwn fox jumps over teh lazy dog and runs around teh park"
        let policy = service.requestPolicy(for: text)

        let result = try await service.resolveCorrectionWithRetry(
            text: text,
            requestPolicy: policy
        ) { _, _, _ in
            callCount += 1
            if callCount == 1 {
                // First attempt: truncated output (< 50% of input)
                return GroqService.ParsedCompletion(
                    content: "the quick brown",
                    inputTokens: 20,
                    outputTokens: 5,
                    finishReason: "length"
                )
            }
            // Retry: full output
            return GroqService.ParsedCompletion(
                content: "the quick brown fox jumps over the lazy dog and runs around the park",
                inputTokens: 20,
                outputTokens: 15,
                finishReason: "stop"
            )
        }

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.correctedText, "the quick brown fox jumps over the lazy dog and runs around the park")
    }

    func testResolveCorrectionWithRetryRetriesOnEmptyContent() async throws {
        var observedMaxCompletionTokens: [Int] = []
        let text = "teh quik brwn fox"
        let policy = service.requestPolicy(for: text)

        let result = try await service.resolveCorrectionWithRetry(
            text: text,
            requestPolicy: policy
        ) { maxCompletionTokens, _, _ in
            observedMaxCompletionTokens.append(maxCompletionTokens)
            if observedMaxCompletionTokens.count == 1 {
                return GroqService.ParsedCompletion(content: "", inputTokens: 8, outputTokens: 2, finishReason: "stop")
            }
            return GroqService.ParsedCompletion(content: "the quick brown fox", inputTokens: 8, outputTokens: 6, finishReason: "stop")
        }

        XCTAssertEqual(observedMaxCompletionTokens.count, 2)
        XCTAssertEqual(result.correctedText, "the quick brown fox")
    }
}
