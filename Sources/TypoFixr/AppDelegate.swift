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
    private var permissionPollingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy FIRST (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Initialize services
        hotkeyService = HotkeyService(appState: appState)
        textCorrectionService = TextCorrectionService(appState: appState)

        // Listen for show settings notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings),
            name: NSNotification.Name("ShowSettings"),
            object: nil
        )

        // Subscribe to correction triggers
        appState.$shouldTriggerCorrection
            .filter { $0 }
            .sink { [weak self] _ in
                self?.triggerCorrection()
                self?.appState.shouldTriggerCorrection = false
            }
            .store(in: &cancellables)

        // Subscribe to icon state changes
        appState.$iconState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        // Subscribe to keyboard shortcut changes
        appState.$keyboardShortcut
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hotkeyService.registerHotkey()
            }
            .store(in: &cancellables)

        // Start network monitoring
        NetworkMonitor.shared.start()

        // Subscribe to network connectivity changes
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                if !isConnected {
                    self.appState.setIconState(.offline)
                } else if self.appState.iconState == .offline {
                    self.appState.setIconState(.normal)
                }
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
            button.image = TypoFixrBranding.menuBarTemplateImage()
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
    
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        appState.hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Update icon based on permission status
        if !appState.hasAccessibilityPermission {
            appState.setIconState(.noPermission)
        }
    }
    
    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        switch appState.iconState {
        case .processing:
            button.image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90", accessibilityDescription: "Processing")?.withSymbolConfiguration(config)
        case .success:
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")?.withSymbolConfiguration(config)
        case .error:
            button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error")?.withSymbolConfiguration(config)
        case .noPermission:
            button.image = NSImage(systemSymbolName: "keyboard.badge.exclamationmark", accessibilityDescription: "Permission Required")?.withSymbolConfiguration(config)
        case .offline:
            button.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "Offline")?.withSymbolConfiguration(config)
        case .normal:
            button.image = TypoFixrBranding.menuBarTemplateImage(pointSize: 16)
        }
    }
    
    private func triggerCorrection() {
        Task {
            await textCorrectionService.performCorrection()
        }
    }
    
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    @objc func showSettings() {
        // Don't show settings if a security alert is being displayed
        guard !appState.isShowingSecurityAlert else { return }

        // Close popover first
        popover?.performClose(nil)

        // Small delay to let popover close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            // Check again after delay
            guard !appState.isShowingSecurityAlert else { return }
            // Close existing settings window if any
            settingsWindow?.close()
            settingsWindow = nil

            let settingsView = SettingsView()
                .environmentObject(appState)

            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.title = "TypoFixr Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 520, height: 440))
            window.center()

            settingsWindow = window

            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
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
        window.title = "Welcome to TypoFixr"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 640, height: 560))
        window.minSize = NSSize(width: 640, height: 560)
        window.maxSize = NSSize(width: 640, height: 560)
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Cancel any existing polling
        permissionPollingTimer?.invalidate()

        // Poll for permission granted
        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

            if trusted {
                timer.invalidate()
                self?.permissionPollingTimer = nil
                DispatchQueue.main.async {
                    self?.appState.hasAccessibilityPermission = true
                    self?.appState.setIconState(.normal)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
    }
}
