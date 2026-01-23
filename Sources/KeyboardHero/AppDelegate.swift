import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState: AppState!
    
    private var cancellables = Set<AnyCancellable>()
    private var hotkeyService: HotkeyService!
    private var textCorrectionService: TextCorrectionService!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize app state
        appState = AppState()
        
        // Initialize services
        hotkeyService = HotkeyService(appState: appState)
        textCorrectionService = TextCorrectionService(appState: appState)
        
        // Set up menu bar
        setupMenuBar()
        
        // Check accessibility permission
        checkAccessibilityPermission()
        
        // Register hotkey
        hotkeyService.registerHotkey()
        
        // Subscribe to correction triggers
        appState.$shouldTriggerCorrection
            .filter { $0 }
            .sink { [weak self] _ in
                self?.triggerCorrection()
                self?.appState.shouldTriggerCorrection = false
            }
            .store(in: &cancellables)
        
        // Show onboarding if first launch or no permission
        if !appState.hasCompletedOnboarding || !appState.hasAccessibilityPermission {
            showOnboarding()
        }
        
        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Hero")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
        )
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    func closePopover() {
        popover.performClose(nil)
    }
    
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        appState.hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Update icon based on permission status
        updateMenuBarIcon()
    }
    
    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        
        if appState.isProcessing {
            // Show loading indicator
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90", accessibilityDescription: "Processing")?.withSymbolConfiguration(config)
        } else if !appState.hasAccessibilityPermission {
            // Show warning
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: "keyboard.badge.exclamationmark", accessibilityDescription: "Permission Required")?.withSymbolConfiguration(config)
        } else if appState.lastError != nil {
            // Show error state
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "Error")?.withSymbolConfiguration(config)
        } else {
            // Normal state
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Hero")?.withSymbolConfiguration(config)
        }
    }
    
    private func triggerCorrection() {
        Task {
            await textCorrectionService.performCorrection()
            await MainActor.run {
                updateMenuBarIcon()
            }
        }
    }
    
    private func showOnboarding() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if #available(macOS 13.0, *) {
                NSApp.openWindow(id: "onboarding")
            }
        }
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Poll for permission granted
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if trusted {
                timer.invalidate()
                DispatchQueue.main.async {
                    self?.appState.hasAccessibilityPermission = true
                    self?.updateMenuBarIcon()
                }
            }
        }
    }
}
