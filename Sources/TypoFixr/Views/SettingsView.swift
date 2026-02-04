import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            ShortcutSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Shortcut", systemImage: "keyboard")
                }
            
            APISettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("API", systemImage: "key")
                }
            
            SecurityPrivacySettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
                    .onAppear {
                        launchAtLogin = getLaunchAtLogin()
                    }
            }
            
            Section {
                HStack {
                    Text("Accessibility Permission")
                    Spacer()
                    if appState.hasAccessibilityPermission {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Button("Grant Access") {
                            AppHelpers.openAccessibilitySettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silent failure - user will see toggle doesn't stick
        }
    }

    private func getLaunchAtLogin() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Shortcut Settings
struct ShortcutSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecording = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard Shortcut")
                        .font(.headline)
                    
                    Text("Press this shortcut to fix the text in the currently focused text field.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        ShortcutRecorderView(
                            config: $appState.keyboardShortcut,
                            isRecording: $isRecording,
                            errorMessage: $errorMessage
                        )
                        .frame(width: 150)
                        
                        if isRecording {
                            Text("Press keys...")
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Reset to Default") {
                            appState.keyboardShortcut = KeyboardShortcutConfig(
                                keyCode: 2, // D key
                                modifiers: [.command, .shift]
                            )
                        }
                        .disabled(isRecording)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Section {
                Text("Default: ⌘⇧D (Command + Shift + D)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcut Recorder
struct ShortcutRecorderView: View {
    @Binding var config: KeyboardShortcutConfig
    @Binding var isRecording: Bool
    @Binding var errorMessage: String?

    @State private var eventMonitor: Any?

    var body: some View {
        Button(action: { startRecording() }) {
            HStack {
                if isRecording {
                    Text("Press shortcut... (Esc to cancel)")
                        .foregroundColor(.secondary)
                } else {
                    Text(config.displayString)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isRecording ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else {
            stopRecording()
            return
        }

        isRecording = true
        errorMessage = nil

        // Use local event monitor to capture key events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil // Consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Handle Escape to cancel
        if event.keyCode == 53 { // Escape key
            stopRecording()
            return
        }

        // Build modifier set
        var modifiers: Set<KeyboardShortcutConfig.ModifierKey> = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }

        // Need at least one modifier
        guard !modifiers.isEmpty else {
            errorMessage = "Shortcut must include at least one modifier (⌘, ⇧, ⌥, or ⌃)"
            return
        }

        let keyCode = UInt32(event.keyCode)

        // Check if reserved
        if HotkeyService.isReservedShortcut(keyCode, modifiers: modifiers) {
            errorMessage = "This shortcut is reserved by the system"
            stopRecording()
            return
        }

        // Update config
        config = KeyboardShortcutConfig(keyCode: keyCode, modifiers: modifiers)
        errorMessage = nil
        stopRecording()
    }
}

// MARK: - API Settings
struct APISettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAPIKey = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Groq API Key")
                        .font(.headline)

                    Text("Required to use TypoFixr. Corrections run on Groq-hosted OpenAI GPT-OSS 20B. Get your API key from console.groq.com")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if showAPIKey {
                            TextField("gsk_...", text: $appState.groqApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("gsk_...", text: $appState.groqApiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    if appState.groqApiKey.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("API key required for corrections")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !appState.groqApiKey.hasPrefix("gsk_") {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("API key should start with 'gsk_'")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API key configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                    if let url = URL(string: "https://console.groq.com/keys") {
                    Link("Get API Key", destination: url)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Security & Privacy Settings
struct SecurityPrivacySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showClearHistoryConfirmation = false
    
    var body: some View {
        Form {
            // Privacy Section
            Section {
                HStack {
                    Button("Clear All History") {
                        showClearHistoryConfirmation = true
                    }
                    .foregroundColor(.red)

                    Spacer()

                    Text("\(appState.correctionHistory.count) corrections in memory")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Privacy", systemImage: "eye.slash")
            }
            
            // Security Section
            Section {
                Toggle("Security Warnings", isOn: $appState.securityWarningsEnabled)
                    .help("Show warnings when text contains potential prompt injections or sensitive data")
                
                Text("Warns before sending text that may contain credit card numbers, passwords, or suspicious patterns.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Security", systemImage: "shield")
            }
            
            // Rate Limiting Section
            Section {
                Stepper("Max \(appState.correctionsPerMinuteLimit) corrections/minute",
                        value: $appState.correctionsPerMinuteLimit,
                        in: 5...30)
                
                Stepper("Max \(appState.correctionsPerHourLimit) corrections/hour",
                        value: $appState.correctionsPerHourLimit,
                        in: 20...500)
            } header: {
                Label("Rate Limiting", systemImage: "gauge.with.dots.needle.50percent")
            }
            
            // Spending Cap Section
            Section {
                Toggle("Enable Spending Cap", isOn: $appState.spendingCapEnabled)
                
                if appState.spendingCapEnabled {
                    Stepper("Limit: \(formatTokens(appState.monthlyTokenLimit)) tokens/month",
                            value: $appState.monthlyTokenLimit,
                            in: 10000...1000000,
                            step: 10000)
                    
                    let stats = appState.getCurrentUsageStats()
                    HStack {
                        Text("Current usage:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(formatTokens(stats.monthlyTokens)) tokens this month")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            } header: {
                Label("Cost Control", systemImage: "dollarsign.circle")
            }
            
            // Data Notice
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Your text is sent to Groq-hosted OpenAI GPT-OSS 20B for processing")
                            .font(.caption)
                    }
                    
                    if let url = URL(string: "https://groq.com/privacy-policy/") {
                        Link("View Groq Privacy Policy", destination: url)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text("This will permanently remove all correction history.")
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.0fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("TypoFixr")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Fix typos and grammar mistakes instantly while preserving your writing style.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 8) {
                if let url = URL(string: "https://typofixr.com/privacy") {
                    Link("Privacy Policy", destination: url)
                }
                if let url = URL(string: "https://typofixr.com/terms") {
                    Link("Terms of Service", destination: url)
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
