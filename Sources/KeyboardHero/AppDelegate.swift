import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState = AppState()

    private var cancellables = Set<AnyCancellable>()
    private var hotkeyService: HotkeyService!
    private var textCorrectionService: TextCorrectionService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy FIRST (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Initialize services
        hotkeyService = HotkeyService(appState: appState)
        textCorrectionService = TextCorrectionService(appState: appState)

        // Subscribe to correction triggers
        appState.$shouldTriggerCorrection
            .filter { $0 }
            .sink { [weak self] _ in
                self?.triggerCorrection()
                self?.appState.shouldTriggerCorrection = false
            }
            .store(in: &cancellables)

        // Check if onboarding is needed
        if !appState.hasCompletedOnboarding {
            // First launch: show only onboarding, no menu bar yet
            showOnboarding()

            // Watch for onboarding completion
            appState.$hasCompletedOnboarding
                .filter { $0 }
                .first()
                .sink { [weak self] _ in
                    self?.onOnboardingCompleted()
                }
                .store(in: &cancellables)
        } else {
            // Already onboarded: set up menu bar and register hotkey
            DispatchQueue.main.async { [self] in
                setupMenuBar()
                checkAccessibilityPermission()
                hotkeyService.registerHotkey()
            }
        }
    }

    private func onOnboardingCompleted() {
        DispatchQueue.main.async { [self] in
            // Close onboarding window
            onboardingWindow?.close()

            // Set up menu bar
            setupMenuBar()
            checkAccessibilityPermission()

            // Register hotkey
            hotkeyService.registerHotkey()

            // Open settings window
            showSettings()
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Hero") {
                button.image = image
            } else {
                // Fallback to text if SF Symbol doesn't work
                button.title = "⌨️"
            }
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
    
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    @objc func showSettings() {
        // Close popover if open
        popover?.performClose(nil)

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.title = "Keyboard Hero Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 380))
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if let window = onboardingWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let onboardingView = OnboardingView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("onboarding")
        window.title = "Welcome to Keyboard Hero"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 500))
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
