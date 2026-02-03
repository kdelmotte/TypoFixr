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

    func testSystemPromptContainsContextualDisambiguationRules() {
        let prompt = service.buildSystemPrompt(languagePreference: "auto")

        XCTAssertTrue(prompt.contains("For heavily misspelled tokens, choose the most likely in-context word, not the smallest character edit."))
        XCTAssertTrue(prompt.contains("Do not default unknown tokens to short function words (not, to, of, in, on, at, for, or, an, a) unless grammar clearly requires it."))
        XCTAssertTrue(prompt.contains("Prefer the candidate that matches the grammatical role of surrounding words."))
    }

    func testSystemPromptContainsAmbiguityExamples() {
        let prompt = service.buildSystemPrompt(languagePreference: "auto")

        XCTAssertTrue(prompt.contains("Input: \"The si the foithb ntot\""))
        XCTAssertTrue(prompt.contains("Output: \"This is the fourth note\""))
        XCTAssertTrue(prompt.contains("Input: \"This is teh fith ntot\""))
        XCTAssertTrue(prompt.contains("Output: \"This is the fifth note\""))
    }

    func testPromptVersionIsDefinedForTraceability() {
        XCTAssertEqual(service.promptVersion, "v2-contextual-deterministic")
    }
}
