import AppKit
import Foundation

/// Service for interacting with text fields in other applications via macOS Accessibility APIs
class AccessibilityService {
    static let shared = AccessibilityService()
    
    private init() {}
    
    // MARK: - Text Field Information
    struct TextFieldInfo {
        let element: AXUIElement
        let fullText: String
        let selectedText: String?
        let selectedRange: CFRange?
        let cursorPosition: Int?
        let appBundleId: String?
        let fieldSignature: String
        let isEditable: Bool
    }
    
    // MARK: - Get Current Text Field
    func getCurrentTextField() -> TextFieldInfo? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let pid = focusedApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get focused UI element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        let axElement = element as! AXUIElement
        
        // Check if it's a text field/area
        guard isTextElement(axElement) else {
            return nil
        }
        
        // Get text content
        let fullText = getAttributeValue(axElement, kAXValueAttribute as CFString) as? String ?? ""
        
        // Get selected text
        let selectedText = getAttributeValue(axElement, kAXSelectedTextAttribute as CFString) as? String
        
        // Get selected range
        var selectedRange: CFRange? = nil
        if let rangeValue = getAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString) {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                selectedRange = range
            }
        }
        
        // Get cursor position (start of selection)
        let cursorPosition = selectedRange.map { Int($0.location) }
        
        // Check if editable
        let isEditable = isElementEditable(axElement)
        
        // Generate field signature for bookmark tracking
        let signature = generateFieldSignature(axElement, appBundleId: focusedApp.bundleIdentifier)
        
        return TextFieldInfo(
            element: axElement,
            fullText: fullText,
            selectedText: selectedText,
            selectedRange: selectedRange,
            cursorPosition: cursorPosition,
            appBundleId: focusedApp.bundleIdentifier,
            fieldSignature: signature,
            isEditable: isEditable
        )
    }

    // MARK: - Helper Methods
    private func isTextElement(_ element: AXUIElement) -> Bool {
        guard let role = getAttributeValue(element, kAXRoleAttribute as CFString) as? String else {
            return false
        }
        
        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField"
        ]
        
        return textRoles.contains(role)
    }
    
    private func isElementEditable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }
    
    private func getAttributeValue(_ element: AXUIElement, _ attribute: CFString) -> Any? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }
    
    private func generateFieldSignature(_ element: AXUIElement, appBundleId: String?) -> String {
        // Create a signature based on element properties
        var parts: [String] = []
        
        if let bundleId = appBundleId {
            parts.append(bundleId)
        }
        
        if let role = getAttributeValue(element, kAXRoleAttribute as CFString) as? String {
            parts.append(role)
        }
        
        if let identifier = getAttributeValue(element, kAXIdentifierAttribute as CFString) as? String {
            parts.append(identifier)
        }
        
        if let description = getAttributeValue(element, kAXDescriptionAttribute as CFString) as? String {
            parts.append(description)
        }
        
        // Get position as part of signature
        var position: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
           let posValue = position {
            var point = CGPoint()
            if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
                parts.append("\(Int(point.x)),\(Int(point.y))")
            }
        }
        
        return parts.joined(separator: ":")
    }
    
    private func extractCurrentParagraph(_ text: String, cursorPosition: Int) -> (text: String, startIndex: Int) {
        let nsText = text as NSString
        let safePosition = min(cursorPosition, text.count)
        
        // Find paragraph boundaries
        var startIndex = safePosition
        var endIndex = safePosition
        
        // Search backward for newline or start
        while startIndex > 0 {
            let prevIndex = startIndex - 1
            let char = nsText.character(at: prevIndex)
            if char == 10 || char == 13 { // \n or \r
                break
            }
            startIndex = prevIndex
        }
        
        // Search forward for newline or end
        while endIndex < text.count {
            let char = nsText.character(at: endIndex)
            if char == 10 || char == 13 {
                break
            }
            endIndex += 1
        }
        
        let paragraphText = nsText.substring(with: NSRange(location: startIndex, length: endIndex - startIndex))
        return (paragraphText, startIndex)
    }
}
