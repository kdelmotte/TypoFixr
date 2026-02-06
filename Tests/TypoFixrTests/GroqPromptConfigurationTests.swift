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

        XCTAssertEqual(maxCompletionTokens, 4096)
        XCTAssertNil(requestBody["max_tokens"], "max_tokens should not be sent for GPT-OSS responses")
    }

    func testRequestBodyUsesMinimumBudgetForVeryShortInput() {
        let requestBody = service.buildRequestBody(text: "typo", languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 4096)
    }

    func testRequestBodyUsesScaledBudgetFor1300Characters() {
        // >= 300 chars → medium overhead (3072), medium floor (16384): max(16384, 1300 + 3072) = 16384
        let longInput = String(repeating: "a", count: 1_300)
        let requestBody = service.buildRequestBody(text: longInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 16_384)
    }

    func testRequestBodyUsesScaledBudgetFor4199Characters() {
        // >= 300 chars → medium overhead (3072), medium floor (16384): max(16384, 4199 + 3072) = 16384
        let nearThresholdInput = String(repeating: "a", count: 4_199)
        let requestBody = service.buildRequestBody(text: nearThresholdInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 16_384)
    }

    func testRequestBodyUsesScaledBudgetFor4200Characters() {
        // >= 300 chars → medium overhead (3072), medium floor (16384): max(16384, 4200 + 3072) = 16384
        let boundaryInput = String(repeating: "a", count: 4_200)
        let requestBody = service.buildRequestBody(text: boundaryInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 16_384)
    }

    func testRequestBodyUsesScaledBudgetFor4800Characters() {
        // >= 300 chars → medium overhead (3072), medium floor (16384): max(16384, 4800 + 3072) = 16384
        let veryLongInput = String(repeating: "a", count: 4_800)
        let requestBody = service.buildRequestBody(text: veryLongInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 16_384)
    }

    func testRequestBodyUsesLowReasoningEffortByDefault() {
        let requestBody = service.buildRequestBody(text: "teh quik brwn fox", languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "low")
    }

    func testRequestBodyUsesMediumReasoningEffortForLongInputByDefault() {
        // >= 300 chars → medium reasoning effort
        let longInput = String(repeating: "a", count: 1_300)
        let requestBody = service.buildRequestBody(text: longInput, languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "medium")
    }

    func testRequestBodyUsesLowReasoningEffortJustBelowThreshold() {
        // 299 chars → low reasoning effort + standard overhead (2048)
        let input = String(repeating: "a", count: 299)
        let requestBody = service.buildRequestBody(text: input, languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "low")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 4096)
    }

    func testRequestBodyUsesMediumReasoningEffortAtThreshold() {
        // Exactly 300 chars → medium reasoning effort + medium floor (16384)
        let input = String(repeating: "a", count: 300)
        let requestBody = service.buildRequestBody(text: input, languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 16384)
    }

    func testRequestBodyUsesMediumReasoningEffortAboveThreshold() {
        // 500 chars → medium reasoning effort + medium floor (16384)
        let input = String(repeating: "a", count: 500)
        let requestBody = service.buildRequestBody(text: input, languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(requestBody["max_completion_tokens"] as? Int, 16384)
    }

    func testRequestBodyAllowsReasoningEffortOverride() {
        let requestBody = service.buildRequestBody(
            text: "teh quik brwn fox",
            languagePreference: "auto",
            reasoningEffort: "medium"
        )
        XCTAssertEqual(requestBody["reasoning_effort"] as? String, "medium")
    }

    func testRequestBodyWrapsUserTextInUserTextTags() {
        let input = "teh quik brwn fox"
        let requestBody = service.buildRequestBody(text: input, languagePreference: "auto")

        guard let messages = requestBody["messages"] as? [[String: Any]], messages.count == 1 else {
            XCTFail("Expected one user message in request body (instructions + user text combined)")
            return
        }

        let userMessage = messages[0]
        XCTAssertEqual(userMessage["role"] as? String, "user")
        let content = userMessage["content"] as? String ?? ""
        XCTAssertTrue(content.contains("<instructions>"), "User message should contain instructions")
        XCTAssertTrue(content.contains("<user_text>\(input)</user_text>"), "User message should contain wrapped user text")
    }

    func testSystemPromptContainsNoChangeMarkerContract() {
        let prompt = service.buildInstructions(languagePreference: "auto")

        XCTAssertTrue(prompt.contains("__NO_CHANGES__"))
        XCTAssertTrue(prompt.contains("If the input truly needs zero corrections, output EXACTLY"))
    }

    func testInstructionsDoNotContainRetryTag() {
        let prompt = service.buildInstructions(languagePreference: "auto")
        XCTAssertFalse(prompt.contains("<retry>"))
    }

    func testRequestBodyIncludesHiddenReasoningFormat() {
        let requestBody = service.buildRequestBody(text: "teh quik brwn fox", languagePreference: "auto")
        XCTAssertEqual(requestBody["reasoning_format"] as? String, "hidden")
    }

    func testPromptVersionIsDefinedForTraceability() {
        XCTAssertEqual(service.promptVersion, "v5-single-pass")
    }
}
