import XCTest
@testable import TypoFixr

final class GroqPromptConfigurationTests: XCTestCase {
    private let service = GroqService.shared

    func testRequestBodyUsesDeterministicDecoding() {
        let requestBody = service.buildRequestBody(text: "The si the foithb ntot", languagePreference: "auto")

        guard let temperature = requestBody["temperature"] as? Double else {
            XCTFail("Expected deterministic temperature field in request body")
            return
        }
        guard let topP = requestBody["top_p"] as? Double else {
            XCTFail("Expected deterministic top_p field in request body")
            return
        }
        guard let n = requestBody["n"] as? Int else {
            XCTFail("Expected candidate count (n) field in request body")
            return
        }

        XCTAssertEqual(temperature, 0.0)
        XCTAssertEqual(topP, 1.0)
        XCTAssertEqual(n, 1)
    }

    func testRequestBodyUsesGroqHostedGptOss20BModel() {
        let requestBody = service.buildRequestBody(text: "The si the foithb ntot", languagePreference: "auto")

        guard let model = requestBody["model"] as? String else {
            XCTFail("Expected model field in request body")
            return
        }

        XCTAssertEqual(model, "openai/gpt-oss-20b")
    }

    func testRequestBodyUsesMaxCompletionTokensField() {
        let requestBody = service.buildRequestBody(text: "teh quik brwn fox", languagePreference: "auto")

        guard let maxCompletionTokens = requestBody["max_completion_tokens"] as? Int else {
            XCTFail("Expected max_completion_tokens field in request body")
            return
        }

        XCTAssertGreaterThanOrEqual(maxCompletionTokens, 384)
        XCTAssertLessThanOrEqual(maxCompletionTokens, 1792)
        XCTAssertNil(requestBody["max_tokens"], "max_tokens should not be sent for GPT-OSS responses")
    }

    func testRequestBodyUsesMinimumBudgetForVeryShortInput() {
        let requestBody = service.buildRequestBody(text: "typo", languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 384)
    }

    func testRequestBodyUsesScaledBudgetFor1300Characters() {
        let longInput = String(repeating: "a", count: 1_300)
        let requestBody = service.buildRequestBody(text: longInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 689)
    }

    func testRequestBodyUsesStandardTierBudgetBelowVeryLongThreshold() {
        let nearThresholdInput = String(repeating: "a", count: 4_199)
        let requestBody = service.buildRequestBody(text: nearThresholdInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 1_655)
    }

    func testRequestBodyUsesVeryLongTierBudgetAt4200Characters() {
        let boundaryInput = String(repeating: "a", count: 4_200)
        let requestBody = service.buildRequestBody(text: boundaryInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 8_192)
    }

    func testRequestBodyUsesVeryLongTierBudgetFor4800Characters() {
        let veryLongInput = String(repeating: "a", count: 4_800)
        let requestBody = service.buildRequestBody(text: veryLongInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 8_192)
    }

    func testRequestBodyUsesLowReasoningEffortByDefault() {
        let requestBody = service.buildRequestBody(text: "teh quik brwn fox", languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "low")
    }

    func testRequestBodyUsesLowReasoningEffortForLongInputByDefault() {
        let longInput = String(repeating: "a", count: 1_300)
        let requestBody = service.buildRequestBody(text: longInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "low")
    }

    func testRequestBodyAllowsReasoningEffortOverrideForRetry() {
        let requestBody = service.buildRequestBody(
            text: "teh quik brwn fox",
            languagePreference: "auto",
            reasoningEffort: "medium",
            verificationPass: true
        )
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "medium")
    }

    func testRequestBodyWrapsUserTextInUserTextTags() {
        let input = "teh quik brwn fox"
        let requestBody = service.buildRequestBody(text: input, languagePreference: "auto")

        guard let messages = requestBody["messages"] as? [[String: Any]], messages.count == 2 else {
            XCTFail("Expected two chat messages in request body")
            return
        }

        let userMessage = messages[1]
        let content = userMessage["content"] as? String
        XCTAssertEqual(content, "<user_text>\(input)</user_text>")
    }

    func testSystemPromptContainsNoChangeMarkerContract() {
        let prompt = service.buildSystemPrompt(languagePreference: "auto")

        XCTAssertTrue(prompt.contains("__NO_CHANGES__"))
        XCTAssertTrue(prompt.contains("If the input truly needs zero corrections, output EXACTLY"))
    }

    func testVerificationPromptContainsVerificationModeInstruction() {
        let prompt = service.buildSystemPrompt(languagePreference: "auto", verificationPass: true)
        XCTAssertTrue(prompt.contains("<verification_mode>"))
        XCTAssertTrue(prompt.contains("__NO_CHANGES__"))
    }

    func testPromptVersionIsDefinedForTraceability() {
        XCTAssertEqual(service.promptVersion, "v3-unified-reliable")
    }
}
