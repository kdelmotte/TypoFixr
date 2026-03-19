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
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            AppHelpers.requestAccessibilityPermission(source: .settings)
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
                            appState.keyboardShortcut = .defaultConfig
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

    private var apiKeyValidationState: GroqAPIKeyValidationState {
        GroqAPIKeyValidationState(apiKey: appState.groqApiKey)
    }

    private var apiKeyValidationTint: Color {
        switch apiKeyValidationState {
        case .empty:
            return .orange
        case .invalidFormat:
            return .orange
        case .valid:
            return .green
        }
    }

    private var apiKeyValidationMessage: String {
        switch apiKeyValidationState {
        case .empty:
            return "Paste your full Groq API key to enable corrections."
        case .invalidFormat:
            return "Paste the full key from console.groq.com/keys, including the prefix."
        case .valid:
            return "API key configured"
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Groq API Key")
                        .font(.headline)

                    Text("Required to use TypoFixr. Paste the full key from console.groq.com/keys. Corrections run on Groq-hosted OpenAI GPT-OSS 20B.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if showAPIKey {
                            TextField("Paste full API key", text: $appState.groqApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Paste full API key", text: $appState.groqApiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    InlineValidationRow(
                        systemImage: apiKeyValidationState.iconSystemName,
                        tint: apiKeyValidationTint,
                        message: apiKeyValidationMessage
                    )
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
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TypoFixr stores correction history locally on this Mac so recent fixes can appear in the menu bar and be reverted when needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Clear Local History…") {
                        showClearHistoryConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("Clearing history removes saved corrections and local usage records from this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Privacy", systemImage: "eye.slash")
            }
            
            Section {
                Toggle("Security Warnings", isOn: $appState.securityWarningsEnabled)
                    .help("Show warnings when text contains potential prompt injections or sensitive data")
                
                Text("Warns before sending text that may contain credit card numbers, passwords, or suspicious patterns.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Security", systemImage: "shield")
            }
            
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
        .alert("Clear Local History", isPresented: $showClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                appState.clearHistory()
            }
        } message: {
            Text("This will permanently remove the locally stored correction history and usage records on this Mac.")
        }
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            TypoFixrMark(size: 72)
            
            Text("TypoFixr")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("A focused menu bar utility for fixing selected text with your own Groq API key.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            HStack(spacing: 10) {
                AboutBadge(label: "Menu bar")
                AboutBadge(label: "BYO Groq key")
                AboutBadge(label: "Undo friendly")
            }
            
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

struct AboutBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(TypoFixrBrandPalette.blue.opacity(0.12))
            .clipShape(Capsule())
    }
}
