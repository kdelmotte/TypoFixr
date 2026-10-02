import XCTest
@testable import TypoFixr

private actor RecordingTransport: ChatCompletionTransport {
    private(set) var inputs: [String] = []
    var truncated: Bool
    init(truncated: Bool = false) { self.truncated = truncated }
    func performChatCompletionRequest(requestBody: [String: Any], apiKey: String) async throws -> GroqService.ParsedCompletion {
        let content = (requestBody["messages"] as! [[String: String]])[0]["content"]!
        let text = content.components(separatedBy: "<user_text>").last!.components(separatedBy: "</user_text>")[0]
        inputs.append(text)
        // Completing out of order must not scramble the list.
        if text.contains("first") { try await Task.sleep(nanoseconds: 20_000_000) }
        return .init(content: text.replacingOccurrences(of: "teh", with: "the"), inputTokens: 3, outputTokens: 2,
                     finishReason: truncated ? "length" : "stop")
    }
}

final class GroqTransportTests: XCTestCase {
    func testInjectedTransportCorrectsAndReassemblesInSourceOrder() async throws {
        let transport = RecordingTransport()
        let service = GroqService(transport: transport)
        let result = try await service.correctText("- teh first\n- teh second", apiKey: "test", languagePreference: "auto")
        XCTAssertEqual(result.correctedText, "- the first\n- the second")
        XCTAssertEqual(result.inputTokens, 6)
        let count = await transport.inputs.count
        XCTAssertEqual(count, 2)
    }

    func testIncompleteLeafFailsTheWholeCorrection() async {
        let service = GroqService(transport: RecordingTransport(truncated: true))
        do {
            _ = try await service.correctText("- teh first\n- teh second", apiKey: "test", languagePreference: "auto")
            XCTFail("An incomplete leaf must not be pasted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("finish_reason: length")) }
    }
}
