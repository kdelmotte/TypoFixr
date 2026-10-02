import XCTest
import AppKit
@testable import TypoFixr

final class ClipboardTextEditorTests: XCTestCase {
    @MainActor
    private func clipboard() -> NSPasteboard { NSPasteboard(name: .init("TypoFixrTests.\(UUID().uuidString)")) }

    private func state(pid: pid_t = 101, element: pid_t = 201, window: pid_t = 301,
                       location: CFIndex = 0, text: String = "teh text", value: String? = "teh text") -> FocusedTextState {
        FocusedTextState(pid: pid, element: AXUIElementCreateApplication(element), window: AXUIElementCreateApplication(window),
                         range: CFRange(location: location, length: text.utf16.count), selectedText: text, fieldValue: value)
    }

    func testIdentityRequiresSameAppWindowFieldRangeAndContent() {
        let original = state()
        XCTAssertTrue(original.hasSameSelection(as: state()))
        for changed in [state(pid: 102), state(element: 202), state(window: 302), state(location: 9),
                        state(text: "new text"), state(value: "changed field")] {
            XCTAssertFalse(original.hasSameSelection(as: changed))
        }
    }

    @MainActor
    func testClipboardRestoresAllItemsAndRepresentations() throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("Original", forType: .string)
        rich.setData(Data("{\\rtf1 Original}".utf8), forType: .rtf)
        rich.setData(Data([1, 2, 3, 4]), forType: .tiff)
        let file = NSPasteboardItem()
        file.setString("file:///tmp/example.txt", forType: .fileURL)
        XCTAssertTrue(board.writeObjects([rich, file]))
        let snapshot = board.pasteboardItems!.map { item in Dictionary(uniqueKeysWithValues: item.types.map { ($0, item.data(forType: $0)!) }) }
        let transaction = try ClipboardTransaction(pasteboard: board)
        try transaction.write("Corrected")
        XCTAssertTrue(transaction.restoreIfOwned())
        let restored = board.pasteboardItems!.map { item in Dictionary(uniqueKeysWithValues: item.types.map { ($0, item.data(forType: $0)!) }) }
        XCTAssertEqual(restored, snapshot)
    }

    @MainActor
    func testRestorationNeverOverwritesANewerCopy() throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        let transaction = try ClipboardTransaction(pasteboard: board)
        try transaction.write("Corrected")
        board.clearContents()
        board.setString("User copied this", forType: .string)
        XCTAssertFalse(transaction.restoreIfOwned())
        XCTAssertEqual(board.string(forType: .string), "User copied this")
    }

    @MainActor
    func testClipboardChangedBeforeWriteIsNotOverwritten() throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        let transaction = try ClipboardTransaction(pasteboard: board)
        board.setString("New copy", forType: .string)
        XCTAssertThrowsError(try transaction.write("Corrected"))
        XCTAssertFalse(transaction.restoreIfOwned())
        XCTAssertEqual(board.string(forType: .string), "New copy")
    }

    @MainActor
    func testEmptyClipboardRestoredWithoutStaleContents() throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let transaction = try ClipboardTransaction(pasteboard: board)
        try transaction.write("Corrected")
        XCTAssertTrue(transaction.restoreIfOwned())
        XCTAssertNil(board.string(forType: .string))
    }

    @MainActor
    private func copy(_ text: String?, to board: NSPasteboard) {
        guard let text else { return }
        board.clearContents()
        board.setString(text, forType: .string)
    }

    @MainActor
    func testChangedAXSelectionDoesNotSendPaste() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        board.setString("Keep this", forType: .string)
        var current = state()
        var pastes = 0
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { current }, observeInteractions: false, sendKey: { key, _, _ in
            if key == 8 { self.copy("teh text", to: board) }
            if key == 9 { pastes += 1 }
        })
        let selection = try await editor.captureSelection(characterLimit: 5000)
        current = state(location: 20)
        do {
            try await editor.replaceSelection(selection, with: "the text")
            XCTFail("Expected stale selection to be rejected")
        } catch TextEditingError.destinationChanged { }
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(board.string(forType: .string), "Keep this")
    }

    @MainActor
    func testCopyDuringRequestIsPreservedAtPasteTime() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        board.setString("Before request", forType: .string)
        let current = state()
        var pasted: String?
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { current }, observeInteractions: false, sendKey: { key, _, pid in
            XCTAssertEqual(pid, current.pid)
            if key == 8 { self.copy("teh text", to: board) }
            if key == 9 { pasted = board.string(forType: .string) }
        })
        let selection = try await editor.captureSelection(characterLimit: 5000)
        XCTAssertEqual(board.string(forType: .string), "Before request")
        board.clearContents()
        board.setString("Copied while waiting", forType: .string)
        try await editor.replaceSelection(selection, with: "the text")
        XCTAssertEqual(pasted, "the text")
        XCTAssertEqual(board.string(forType: .string), "Copied while waiting")
    }

    @MainActor
    func testMissingAXMetadataStillCapturesAndPastesUsingCopy() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        board.setString("Original clipboard", forType: .string)
        let target = CorrectionTarget(pid: 101, bundleID: "com.example.webeditor", element: nil, window: nil)
        var commands: [CGKeyCode] = []
        var pasted: String?
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { nil }, captureTarget: { target }, observeInteractions: false,
            sendKey: { key, _, _ in
                commands.append(key)
                if key == 8 { self.copy("teh selected text", to: board) }
                if key == 9 { pasted = board.string(forType: .string) }
            })
        let selection = try await editor.captureSelection(characterLimit: 5000)
        XCTAssertEqual(selection.text, "teh selected text")
        XCTAssertEqual(selection.source, .existingSelection)
        XCTAssertTrue(editor.isSelectionCurrent(selection))
        try await editor.replaceSelection(selection, with: "the selected text")
        XCTAssertEqual(commands, [8, 8, 9])
        XCTAssertEqual(pasted, "the selected text")
        XCTAssertEqual(board.string(forType: .string), "Original clipboard")
    }

    @MainActor
    func testMissingAXMetadataUsesParagraphAndLineFallbacks() async throws {
        for fallbackKey: CGKeyCode in [126, 123] {
            let board = clipboard()
            defer { board.releaseGlobally() }
            var selected = false
            let target = CorrectionTarget(pid: 101, bundleID: nil, element: nil, window: nil)
            let editor = ClipboardTextEditor(pasteboard: board, captureState: { nil }, captureTarget: { target }, observeInteractions: false,
                sendKey: { key, _, _ in
                    if key == fallbackKey { selected = true }
                    if key == 8, selected { self.copy("teh paragraph", to: board) }
                })
            let selection = try await editor.captureSelection(characterLimit: 5000)
            XCTAssertEqual(selection.source, fallbackKey == 126 ? .paragraphFallback : .lineFallback)
            XCTAssertEqual(selection.text, "teh paragraph")
        }
    }

    @MainActor
    func testChangedCopiedTextPreventsPasteWithoutAX() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        let target = CorrectionTarget(pid: 101, bundleID: nil, element: nil, window: nil)
        var current = "original text"
        var pastes = 0
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { nil }, captureTarget: { target }, observeInteractions: false,
            sendKey: { key, _, _ in
                if key == 8 { self.copy(current, to: board) }
                if key == 9 { pastes += 1 }
            })
        let selection = try await editor.captureSelection(characterLimit: 5000)
        current = "different selected text"
        do {
            try await editor.replaceSelection(selection, with: "replacement")
            XCTFail("Changed selection must not be overwritten")
        } catch TextEditingError.destinationChanged { }
        XCTAssertEqual(pastes, 0)
    }

    @MainActor
    func testSwitchingAppsPreventsCopyAndPasteWithoutAX() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        var target = CorrectionTarget(pid: 101, bundleID: nil, element: nil, window: nil)
        var keys: [CGKeyCode] = []
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { nil }, captureTarget: { target }, observeInteractions: false,
            sendKey: { key, _, _ in
                keys.append(key)
                if key == 8 { self.copy("teh text", to: board) }
            })
        let selection = try await editor.captureSelection(characterLimit: 5000)
        target = CorrectionTarget(pid: 202, bundleID: nil, element: nil, window: nil)
        do {
            try await editor.replaceSelection(selection, with: "the text")
            XCTFail("Switched app must not receive commands")
        } catch TextEditingError.destinationChanged { }
        XCTAssertEqual(keys, [8])
    }

    @MainActor
    func testCopyNoOpDoesNotMistakePreviousClipboardForSelectedText() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        board.setString("Unrelated copied text", forType: .string)
        let target = CorrectionTarget(pid: 101, bundleID: nil, element: nil, window: nil)
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { nil }, captureTarget: { target }, observeInteractions: false,
                                         sendKey: { _, _, _ in })
        do {
            _ = try await editor.captureSelection(characterLimit: 5000)
            XCTFail("A no-op copy should yield no selection")
        } catch TextEditingError.noSelection { }
        XCTAssertEqual(board.string(forType: .string), "Unrelated copied text")
    }

    @MainActor
    func testDelayedCopyHandlerIsSupported() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        let target = CorrectionTarget(pid: 101, bundleID: nil, element: nil, window: nil)
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { nil }, captureTarget: { target }, observeInteractions: false,
            sendKey: { key, _, _ in
                if key == 8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.copy("Delayed selected text", to: board) }
                }
            })
        let selection = try await editor.captureSelection(characterLimit: 5000)
        XCTAssertEqual(selection.text, "Delayed selected text")
    }

    @MainActor
    func testKnownEmptyAXSelectionSkipsBlockCopyAndSelectsParagraph() async throws {
        let board = clipboard()
        defer { board.releaseGlobally() }
        var current = state(text: "", value: "teh text")
        let selected = state()
        var keys: [CGKeyCode] = []
        let editor = ClipboardTextEditor(pasteboard: board, captureState: { current }, observeInteractions: false,
            sendKey: { key, _, _ in
                keys.append(key)
                if key == 126 { current = selected }
                if key == 8 { self.copy("teh text", to: board) }
            })
        let result = try await editor.captureSelection(characterLimit: 5000)
        XCTAssertEqual(keys, [126, 8])
        XCTAssertEqual(result.source, .paragraphFallback)
        editor.endSession()
        XCTAssertFalse(editor.isSelectionCurrent(result))
    }
}
