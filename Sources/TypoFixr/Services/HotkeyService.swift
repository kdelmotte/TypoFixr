import Foundation
import AppKit
import Carbon
import HotKey

class HotkeyService {
    private var appState: AppState
    private var hotKey: HotKey?
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func registerHotkey() {
        // Unregister existing hotkey
        hotKey = nil
        
        let config = appState.keyboardShortcut
        
        // Convert our config to HotKey's Key and modifiers
        guard let key = keyCodeToKey(config.keyCode) else {
            print("Invalid key code: \(config.keyCode)")
            return
        }
        
        var modifiers: NSEvent.ModifierFlags = []
        if config.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if config.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        if config.modifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if config.modifiers.contains(.control) {
            modifiers.insert(.control)
        }
        
        hotKey = HotKey(key: key, modifiers: modifiers)
        
        hotKey?.keyDownHandler = { [weak self] in
            self?.handleHotkey()
        }
        
        print("Registered hotkey: \(config.displayString)")
    }
    
    func unregisterHotkey() {
        hotKey = nil
    }
    
    func updateHotkey(config: KeyboardShortcutConfig) {
        appState.keyboardShortcut = config
        registerHotkey()
    }
    
    private func handleHotkey() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if we should toggle revert
            if self.appState.canToggleRevert {
                self.appState.shouldTriggerCorrection = true
                // The correction service will handle the revert logic
            } else {
                self.appState.shouldTriggerCorrection = true
            }
        }
    }
    
    // MARK: - Key Code Conversion
    private func keyCodeToKey(_ keyCode: UInt32) -> Key? {
        // Map common key codes to HotKey's Key enum
        switch keyCode {
        case 0: return .a
        case 1: return .s
        case 2: return .d
        case 3: return .f
        case 4: return .h
        case 5: return .g
        case 6: return .z
        case 7: return .x
        case 8: return .c
        case 9: return .v
        case 11: return .b
        case 12: return .q
        case 13: return .w
        case 14: return .e
        case 15: return .r
        case 16: return .y
        case 17: return .t
        case 18: return .one
        case 19: return .two
        case 20: return .three
        case 21: return .four
        case 22: return .six
        case 23: return .five
        case 24: return .equal
        case 25: return .nine
        case 26: return .seven
        case 27: return .minus
        case 28: return .eight
        case 29: return .zero
        case 30: return .rightBracket
        case 31: return .o
        case 32: return .u
        case 33: return .leftBracket
        case 34: return .i
        case 35: return .p
        case 37: return .l
        case 38: return .j
        case 39: return .quote
        case 40: return .k
        case 41: return .semicolon
        case 42: return .backslash
        case 43: return .comma
        case 44: return .slash
        case 45: return .n
        case 46: return .m
        case 47: return .period
        case 48: return .tab
        case 49: return .space
        case 50: return .grave
        case 96: return .f5
        case 97: return .f6
        case 98: return .f7
        case 99: return .f3
        case 100: return .f8
        case 101: return .f9
        case 103: return .f11
        case 109: return .f10
        case 111: return .f12
        case 118: return .f4
        case 119: return .f2
        case 120: return .f1
        default: return nil
        }
    }
    
    // MARK: - Reserved Shortcuts Check
    static func isReservedShortcut(_ keyCode: UInt32, modifiers: Set<KeyboardShortcutConfig.ModifierKey>) -> Bool {
        // Check for common system shortcuts that shouldn't be overridden
        let reservedCombinations: [(UInt32, Set<KeyboardShortcutConfig.ModifierKey>)] = [
            // Copy, Paste, Cut
            (8, [.command]),   // Cmd+C
            (9, [.command]),   // Cmd+V
            (7, [.command]),   // Cmd+X
            // Undo, Redo
            (6, [.command]),   // Cmd+Z
            (6, [.command, .shift]),   // Cmd+Shift+Z
            // Select All
            (0, [.command]),   // Cmd+A
            // Save
            (1, [.command]),   // Cmd+S
            // Quit
            (12, [.command]),  // Cmd+Q
            // Tab switching
            (48, [.command]),  // Cmd+Tab
        ]
        
        return reservedCombinations.contains { reserved in
            reserved.0 == keyCode && reserved.1 == modifiers
        }
    }
}
