import AppKit
import Foundation

struct CapturedSelection {
    let id: UUID
    let text: String
    let source: TextCorrectionService.SelectionSource
    let appBundleID: String?
    let correctionText: String

    init(id: UUID = UUID(), text: String, source: TextCorrectionService.SelectionSource, appBundleID: String?, correctionText: String? = nil) {
        self.id = id
        self.text = text
        self.source = source
        self.appBundleID = appBundleID
        self.correctionText = correctionText ?? text
    }
}

enum TextEditingError: LocalizedError {
    case noSelection
    case tooLong(Int)
    case destinationChanged
    case clipboardUnavailable
    case eventUnavailable

    var errorDescription: String? {
        switch self {
        case .noSelection: return "Highlight some text and try again."
        case .tooLong(let count): return "Selected text is \(count) characters. Select at most \(AppState.characterLimit)."
        case .destinationChanged: return "The active field or selected text changed. Select your text and try again."
        case .clipboardUnavailable: return "The clipboard could not be preserved. No text was changed."
        case .eventUnavailable: return "Could not send the editing command. No text was changed."
        }
    }
}

@MainActor
protocol CorrectionTextEditing {
    func captureSelection(characterLimit: Int) async throws -> CapturedSelection
    func isSelectionCurrent(_ selection: CapturedSelection) -> Bool
    func replaceSelection(_ selection: CapturedSelection, with text: String) async throws
    func endSession()
}

/// Snapshot the bytes for every representation of every item, including rich text,
/// images and file URLs. A partial snapshot is rejected instead of losing data.
@MainActor
final class ClipboardTransaction {
    private let pasteboard: NSPasteboard
    private let items: [[NSPasteboard.PasteboardType: Data]]
    private let initialChangeCount: Int
    private var ownedChangeCount: Int?
    private var ownedItems: [[NSPasteboard.PasteboardType: Data]]?

    init(pasteboard: NSPasteboard) throws {
        self.pasteboard = pasteboard
        initialChangeCount = pasteboard.changeCount
        items = try Self.snapshot(pasteboard)
        guard pasteboard.changeCount == initialChangeCount else { throw TextEditingError.clipboardUnavailable }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) throws -> [[NSPasteboard.PasteboardType: Data]] {
        try (pasteboard.pasteboardItems ?? []).map { item in
            var result: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw TextEditingError.clipboardUnavailable }
                result[type] = data
            }
            return result
        }
    }

    func write(_ text: String) throws {
        guard pasteboard.changeCount == initialChangeCount, try Self.snapshot(pasteboard) == items,
              pasteboard.changeCount == initialChangeCount else { throw TextEditingError.clipboardUnavailable }
        ownedChangeCount = pasteboard.clearContents()
        ownedItems = []
        let written = pasteboard.setString(text, forType: .string)
        ownedChangeCount = pasteboard.changeCount
        ownedItems = try Self.snapshot(pasteboard)
        guard written else { throw TextEditingError.clipboardUnavailable }
    }

    /// Cmd+C writes on our behalf. Claim that result only after checking the
    /// destination and input activity, then restore it under the same ownership rules.
    func adoptCopyResult() throws {
        let count = pasteboard.changeCount
        let copied = try Self.snapshot(pasteboard)
        guard pasteboard.changeCount == count else { throw TextEditingError.clipboardUnavailable }
        ownedChangeCount = count
        ownedItems = copied
    }

    @discardableResult
    func restoreIfOwned() -> Bool {
        guard let ownedChangeCount, let ownedItems, pasteboard.changeCount == ownedChangeCount,
              let current = try? Self.snapshot(pasteboard), current == ownedItems,
              pasteboard.changeCount == ownedChangeCount else { return false }
        self.ownedChangeCount = nil
        self.ownedItems = nil
        let restoredItems = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        return restoredItems.isEmpty || pasteboard.writeObjects(restoredItems)
    }
}

/// Identity and content must all match; checking only the bundle identifier or
/// whether *some* text is selected does not protect the user's destination.
struct FocusedTextState {
    let pid: pid_t
    let element: AXUIElement
    let window: AXUIElement
    let range: CFRange
    let selectedText: String
    let fieldValue: String?

    func hasSameTarget(as other: Self) -> Bool {
        pid == other.pid && CFEqual(element, other.element) && CFEqual(window, other.window)
    }

    func hasSameSelection(as other: Self) -> Bool {
        hasSameTarget(as: other) && range.location == other.range.location && range.length == other.range.length
            && selectedText == other.selectedText && fieldValue == other.fieldValue
    }

    static func capture() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func axElement(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        guard let element = axElement(attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)),
              let window = axElement(attribute(element, kAXWindowAttribute)),
              let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID(),
              let selected = attribute(element, kAXSelectedTextAttribute) as? String else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else { return nil }
        var range = CFRange()
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return Self(pid: pid, element: element, window: window, range: range,
                    selectedText: selected, fieldValue: attribute(element, kAXValueAttribute) as? String)
    }
}

/// Accessibility is optional context. Web editors may expose neither a text role
/// nor a selected range, but still support the normal Copy/Paste commands.
struct CorrectionTarget {
    let pid: pid_t
    let bundleID: String?
    let element: AXUIElement?
    let window: AXUIElement?
    var isSecure = false

    func matches(_ other: Self) -> Bool {
        guard pid == other.pid else { return false }
        if let element, let current = other.element, !CFEqual(element, current) { return false }
        if let window, let current = other.window, !CFEqual(window, current) { return false }
        return !other.isSecure
    }

    static func capture() -> Self? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let focused = element(attribute(application, kAXFocusedUIElementAttribute))
        let window = element(attribute(application, kAXFocusedWindowAttribute))
        let secure = focused.map { attribute($0, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole } ?? false
        return Self(pid: app.processIdentifier, bundleID: app.bundleIdentifier, element: focused, window: window, isSecure: secure)
    }
}

@MainActor
final class ClipboardTextEditor: CorrectionTextEditing {
    private struct Session {
        let selection: CapturedSelection
        let target: CorrectionTarget
        let state: FocusedTextState?
    }
    private var session: Session?
    private let pasteboard: NSPasteboard
    private let captureState: () -> FocusedTextState?
    private let captureTarget: () -> CorrectionTarget?
    private let sendKey: (CGKeyCode, CGEventFlags, pid_t) async throws -> Void
    private let observeInteractions: Bool
    private var inputMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var userInteracted = false
    private static let generatedEventMarker: Int64 = 0x5459504F464958

    init(pasteboard: NSPasteboard = .general,
         captureState: @escaping () -> FocusedTextState? = FocusedTextState.capture,
         captureTarget: (() -> CorrectionTarget?)? = nil,
         observeInteractions: Bool = true,
         sendKey: @escaping (CGKeyCode, CGEventFlags, pid_t) async throws -> Void = ClipboardTextEditor.postKey) {
        self.pasteboard = pasteboard
        self.captureState = captureState
        self.captureTarget = captureTarget ?? {
            if let state = captureState() {
                return CorrectionTarget(pid: state.pid, bundleID: NSRunningApplication(processIdentifier: state.pid)?.bundleIdentifier,
                                        element: state.element, window: state.window)
            }
            return CorrectionTarget.capture()
        }
        self.observeInteractions = observeInteractions
        self.sendKey = sendKey
    }

    func captureSelection(characterLimit: Int) async throws -> CapturedSelection {
        endSession()
        try Task.checkCancellation()
        guard let target = captureTarget(), !target.isSecure else { throw TextEditingError.noSelection }
        var source = TextCorrectionService.SelectionSource.existingSelection
        var text: String?
        // When AX explicitly reports no selection, avoid block-copy in apps like
        // Notion. Missing AX information is not evidence that selection is absent.
        if captureState()?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true {
            text = try await copySelection(in: target)
        }
        if text == nil {
            let strategies: [(CGKeyCode, CGEventFlags, TextCorrectionService.SelectionSource)] = [
                (126, [.maskAlternate, .maskShift], .paragraphFallback),
                (123, [.maskCommand, .maskShift], .lineFallback)
            ]
            for (key, flags, strategy) in strategies {
                try Task.checkCancellation()
                guard targetIsCurrent(target) else { throw TextEditingError.destinationChanged }
                try await sendKey(key, flags, target.pid)
                await Self.settle(for: 0.05)
                text = try await copySelection(in: target)
                source = strategy
                if text != nil { break }
            }
        }
        guard let text else { throw TextEditingError.noSelection }
        guard text.count <= characterLimit else { throw TextEditingError.tooLong(text.count) }
        try Task.checkCancellation()
        guard targetIsCurrent(target) else { throw TextEditingError.destinationChanged }
        let selection = CapturedSelection(text: text, source: source, appBundleID: target.bundleID,
                                          correctionText: Self.normalizeClipboardText(text, target: target, source: source))
        session = Session(selection: selection, target: target, state: captureState())
        startObservingInteraction()
        return selection
    }

    private func targetIsCurrent(_ target: CorrectionTarget) -> Bool {
        guard let current = captureTarget() else { return false }
        return target.matches(current)
    }

    /// Read via the same Copy command the user can use. Restore the entire
    /// clipboard immediately, so it stays available during the network request.
    private func copySelection(in target: CorrectionTarget) async throws -> String? {
        guard !userInteracted, targetIsCurrent(target) else { throw TextEditingError.destinationChanged }
        let clipboard = try ClipboardTransaction(pasteboard: pasteboard)
        defer { clipboard.restoreIfOwned() }
        try clipboard.write("")
        let emptyCount = pasteboard.changeCount
        guard targetIsCurrent(target) else { throw TextEditingError.destinationChanged }
        try await sendKey(8, .maskCommand, target.pid)
        // Wait for delayed copy handlers in Electron/WebKit, without treating stale
        // clipboard contents as a selection when Copy is a no-op.
        for _ in 0..<15 {
            await Self.settle(for: 0.02)
            if pasteboard.changeCount != emptyCount { break }
        }
        guard !userInteracted, targetIsCurrent(target) else { throw TextEditingError.destinationChanged }
        try clipboard.adoptCopyResult()
        try Task.checkCancellation()
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    func isSelectionCurrent(_ selection: CapturedSelection) -> Bool {
        guard !userInteracted, let session, session.selection.id == selection.id,
              targetIsCurrent(session.target) else { return false }
        // Use stronger AX comparisons when available, but do not require them.
        if let original = session.state, let current = captureState() {
            if original.hasSameSelection(as: current) { return true }
            // Some editors drop a programmatic selection while the request is in
            // flight. Only a fallback selection can be reselected, then copy-verified.
            return selection.source != .existingSelection && current.selectedText.isEmpty
                && original.hasSameTarget(as: current) && original.fieldValue == current.fieldValue
        }
        return true
    }

    func replaceSelection(_ selection: CapturedSelection, with text: String) async throws {
        try Task.checkCancellation()
        guard isSelectionCurrent(selection), let session else { throw TextEditingError.destinationChanged }
        var currentText = try await copySelection(in: session.target)
        if currentText == nil, selection.source != .existingSelection {
            guard isSelectionCurrent(selection) else { throw TextEditingError.destinationChanged }
            let key: CGKeyCode = selection.source == .paragraphFallback ? 126 : 123
            let flags: CGEventFlags = selection.source == .paragraphFallback ? [.maskAlternate, .maskShift] : [.maskCommand, .maskShift]
            try await sendKey(key, flags, session.target.pid)
            await Self.settle(for: 0.05)
            currentText = try await copySelection(in: session.target)
        }
        // This check works even when AX text, role, range and element are all absent.
        guard currentText == selection.text, isSelectionCurrent(selection) else { throw TextEditingError.destinationChanged }
        try Task.checkCancellation()
        let clipboard = try ClipboardTransaction(pasteboard: pasteboard)
        defer { clipboard.restoreIfOwned() }
        guard isSelectionCurrent(selection) else { throw TextEditingError.destinationChanged }
        try clipboard.write(text)
        guard isSelectionCurrent(selection) else { throw TextEditingError.destinationChanged }
        try await sendKey(9, .maskCommand, session.target.pid)
        await Self.settle(for: 0.3)
    }

    func endSession() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        inputMonitor = nil
        activationObserver = nil
        userInteracted = false
        session = nil
    }

    private func startObservingInteraction() {
        guard observeInteractions else { return }
        inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.generatedEventMarker else { return }
            MainActor.assumeIsolated { self?.userInteracted = true }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let session = self.session,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if app.processIdentifier != session.target.pid && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self.userInteracted = true
                }
            }
        }
    }

    private static func settle(for seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    private static func normalizeClipboardText(_ text: String, target: CorrectionTarget,
                                               source: TextCorrectionService.SelectionSource) -> String {
        guard target.bundleID == "com.apple.Notes", source != .existingSelection, !text.contains("\n") else { return text }
        for pattern in [#"^\s*[-*•–—]\s*\[(?: |x|X)\]\s+"#, #"^\s*\[(?: |x|X)\]\s+"#, #"^\s*[-*•–—]\s+"#] {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return String(text[range.upperBound...])
            }
        }
        return text
    }

    private static func postKey(_ key: CGKeyCode, _ modifiers: CGEventFlags, _ pid: pid_t) async throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw TextEditingError.destinationChanged }
        let source = CGEventSource(stateID: .hidSystemState)
        let modifierKeys: [(CGEventFlags, CGKeyCode)] = [(.maskShift, 56), (.maskCommand, 55), (.maskAlternate, 58), (.maskControl, 59)]
        var downEvents: [CGEvent] = []
        var upEvents: [CGEvent] = []
        var flags = CGEventFlags()
        func event(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool = false) throws -> CGEvent {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { throw TextEditingError.eventUnavailable }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
            return event
        }
        for (flag, code) in modifierKeys where modifiers.contains(flag) {
            flags.insert(flag)
            downEvents.append(try event(code, down: true, flags: flags, modifier: true))
        }
        downEvents.append(try event(key, down: true, flags: modifiers))
        upEvents.append(try event(key, down: false, flags: modifiers))
        for (flag, code) in modifierKeys.reversed() where modifiers.contains(flag) {
            flags.remove(flag)
            upEvents.append(try event(code, down: false, flags: flags, modifier: true))
        }
        // Restore the original HID event route used by TypoFixr's cross-app workflow.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw TextEditingError.destinationChanged }
        downEvents.forEach { $0.post(tap: .cghidEventTap) }
        await settle(for: 0.01)
        upEvents.forEach { $0.post(tap: .cghidEventTap) }
    }
}
