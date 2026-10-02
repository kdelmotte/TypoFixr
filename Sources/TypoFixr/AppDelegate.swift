import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState = AppRuntime.makeAppState()

    private let accessibilityPermissionPollingInterval: TimeInterval = 1.0
    private let accessibilityPermissionPollingTimeout: TimeInterval = 90.0
    private var cancellables = Set<AnyCancellable>()
    private var hotkeyService: HotkeyService!
    private var textCorrectionService: TextCorrectionService!
    private var permissionPollingTimer: Timer?
    private var permissionPollingDeadline: Date?
    private var permissionPollingSource: AccessibilityGrantSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppRuntime.isRunningTests else { return }
        // Set activation policy FIRST (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
        TelemetryService.shared.track(.appLaunched)

        // Initialize services
        hotkeyService = HotkeyService(appState: appState)
        textCorrectionService = TextCorrectionService(appState: appState)

        // Listen for show settings notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings(_:)),
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

        appState.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.popover?.isShown == true else { return }
                self.refreshPopoverSize()
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

        checkAccessibilityPermission()

        let initialStep = OnboardingGateState(
            hasAccessibilityPermission: appState.hasAccessibilityPermission,
            apiKeyValidationState: GroqAPIKeyValidationState(apiKey: appState.groqApiKey)
        ).initialStep(hasCompletedOnboarding: appState.hasCompletedOnboarding)

        // Returning users retain their menu and settings while repairing setup.
        if appState.hasCompletedOnboarding {
            setupMenuBar()
            hotkeyService.registerHotkey()
        }
        if let initialStep {
            showOnboarding(initialStep: initialStep)
        }
    }

    private func onOnboardingCompleted() {
        DispatchQueue.main.async { [self] in
            // Close onboarding window
            onboardingWindow?.close()
            onboardingWindow = nil

            // Set up menu bar
            setupMenuBar()
            checkAccessibilityPermission()

            // Register hotkey
            hotkeyService.registerHotkey()

            // Open settings window
            showSettingsWindow(origin: .onboardingCompletion)
        }
    }
    
    private func setupMenuBar() {
        guard statusItem == nil else {
            updateMenuBarIcon()
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateMenuBarIcon()

        popover = NSPopover()
        popover.contentSize = NSSize(width: MenuBarView.width, height: 400)
        popover.behavior = .transient
        let controller = NSHostingController(rootView: MenuBarView().environmentObject(appState))
        controller.sizingOptions = []
        popover.contentViewController = controller
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                checkAccessibilityPermission()
                refreshPopoverSize()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    private func refreshPopoverSize() {
        let controller = NSHostingController(rootView: MenuBarView(scrollsContent: false).environmentObject(appState))
        controller.sizingOptions = []
        let measured = controller.sizeThatFits(in: CGSize(width: MenuBarView.width, height: CGFloat.greatestFiniteMagnitude))
        let visibleHeight = statusItem?.button?.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        popover?.contentSize = Self.menuPopoverSize(contentHeight: measured.height, visibleHeight: visibleHeight)
    }

    static func menuPopoverSize(contentHeight: CGFloat, visibleHeight: CGFloat) -> NSSize {
        NSSize(width: MenuBarView.width, height: min(ceil(contentHeight), max(100, min(680, visibleHeight - 48))))
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        updateAccessibilityPermissionState(isTrusted: trusted, source: permissionPollingSource)
    }

    private func updateAccessibilityPermissionState(
        isTrusted: Bool,
        source: AccessibilityGrantSource? = nil
    ) {
        let wasTrusted = appState.hasAccessibilityPermission
        appState.updateAccessibilityPermission(
            isTrusted: isTrusted,
            isConnected: NetworkMonitor.shared.isConnected
        )

        if isTrusted {
            if !wasTrusted, let source {
                TelemetryService.shared.track(.accessibilityPermissionGranted(source: source))
            }

        }
    }
    
    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        button.image = TypoFixrBranding.menuBarImage(for: appState.iconState)
        let description = "\(AppHelpers.productName): \(appState.iconState.statusDescription)"
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    private func triggerCorrection() {
        checkAccessibilityPermission()
        Task {
            await textCorrectionService.performCorrection()
        }
    }
    
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    @objc func showSettings(_ notification: Notification) {
        let section = SettingsSection(rawValue: notification.object as? String ?? "") ?? .general
        showSettingsWindow(origin: .menuBar, section: section)
    }

    private func showSettingsWindow(origin: SettingsOpenSource, section: SettingsSection = .general) {
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

            let settingsView = SettingsView(initialSection: section)
                .environmentObject(appState)

            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.title = "\(AppHelpers.productName) Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 600, height: 520))
            window.contentMinSize = NSSize(width: 560, height: 460)
            window.center()

            settingsWindow = window

            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKeyAndOrderFront(nil)
            TelemetryService.shared.track(.settingsOpened(source: origin))
        }
    }

    private func showOnboarding(initialStep: OnboardingStep = .welcome) {
        if let window = onboardingWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let onboardingLayout = measuredOnboardingLayout()
        let onboardingView = OnboardingView(layout: onboardingLayout, initialStep: initialStep) { [weak self] in
            self?.onOnboardingCompleted()
        }
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: onboardingView)
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("onboarding")
        window.title = "Welcome to \(AppHelpers.productName)"
        window.styleMask = [.titled, .closable]
        window.setContentSize(onboardingLayout.size)
        window.minSize = onboardingLayout.size
        window.maxSize = onboardingLayout.size
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startAccessibilityPermissionPolling(source: .onboarding)
    }

    private func measuredOnboardingLayout() -> OnboardingWindowLayout {
        let visibleFrame = currentVisibleFrame()

        return OnboardingWindowSizer.resolveLayout(for: visibleFrame) { [weak self] step, width, usesCompactAccessibilityLayout in
            self?.measureOnboardingStep(
                step,
                width: width,
                usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
            ) ?? OnboardingWindowLayout.fallback.size.height
        }
    }

    private func currentVisibleFrame() -> CGRect {
        if let screen = onboardingWindow?.screen ?? NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen {
            return screen.visibleFrame
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(origin: .zero, size: OnboardingWindowLayout.fallback.size)
    }

    private func measureOnboardingStep(
        _ step: OnboardingStep,
        width: CGFloat,
        usesCompactAccessibilityLayout: Bool
    ) -> CGFloat {
        let snapshot = OnboardingContentSnapshot.measurement(
            for: step,
            usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
        )

        let shell = OnboardingShell(
            step: step,
            snapshot: snapshot,
            apiKeyText: .constant(snapshot.apiKey),
            primaryButtonTitle: step.primaryButtonTitle(
                hasAccessibilityPermission: snapshot.hasAccessibilityPermission
            ),
            isPrimaryButtonDisabled: step == .apiKey && snapshot.apiKeyValidationState != .valid,
            footerHint: step.footerHint(
                hasAccessibilityPermission: snapshot.hasAccessibilityPermission
            ),
            onBack: step.previous == nil ? nil : {},
            onPrimaryAction: {},
            onToggleAPIKeyVisibility: {},
            fillsWindowHeight: false
        )

        let hostingController = NSHostingController(rootView: shell)
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        let measuredSize = hostingController.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )

        return measuredSize.height
    }
    
    func requestAccessibilityPermission(source: AccessibilityGrantSource) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // A stale grant can prevent the AX prompt appearing. The button still
        // needs to open the panel so the user can repair the existing entry.
        AppHelpers.openAccessibilitySettings()
        startAccessibilityPermissionPolling(source: source)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkAccessibilityPermission()
    }

    private func startAccessibilityPermissionPolling(source: AccessibilityGrantSource) {
        stopAccessibilityPermissionPolling()

        permissionPollingSource = source
        permissionPollingDeadline = Date().addingTimeInterval(accessibilityPermissionPollingTimeout)

        permissionPollingTimer = Timer.scheduledTimer(
            withTimeInterval: accessibilityPermissionPollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.pollAccessibilityPermission()
        }

        if let permissionPollingTimer {
            RunLoop.main.add(permissionPollingTimer, forMode: .common)
        }

        pollAccessibilityPermission()
    }

    private func pollAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        updateAccessibilityPermissionState(isTrusted: trusted, source: permissionPollingSource)

        if trusted {
            stopAccessibilityPermissionPolling()
            return
        }

        if let permissionPollingDeadline, Date() >= permissionPollingDeadline,
           onboardingWindow?.isVisible != true {
            stopAccessibilityPermissionPolling()
        }
    }

    private func stopAccessibilityPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
        permissionPollingDeadline = nil
        permissionPollingSource = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAccessibilityPermissionPolling()
    }
}
