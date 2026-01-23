import SwiftUI

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
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                Picker("Character Limit", selection: $appState.characterLimit) {
                    Text("300 characters").tag(300)
                    Text("500 characters").tag(500)
                    Text("750 characters").tag(750)
                    Text("1000 characters").tag(1000)
                }
                .help("Maximum text length before prompting to select specific text")
                
                Picker("Language", selection: $appState.languagePreference) {
                    Text("Auto-detect").tag("auto")
                    Text("English").tag("English")
                    Text("French").tag("French")
                    Text("Spanish").tag("Spanish")
                    Text("German").tag("German")
                    Text("Italian").tag("Italian")
                    Text("Portuguese").tag("Portuguese")
                }
                .help("Language for corrections (auto-detect recommended)")
            }
            
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
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
                            openAccessibilitySettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        // In a production app, use SMAppService or LaunchAtLogin package
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
    }
    
    private func getLaunchAtLogin() -> Bool {
        UserDefaults.standard.bool(forKey: "launchAtLogin")
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
                                keyCode: 47,
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
                Text("Default: ⌘⇧. (Command + Shift + Period)")
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
    
    var body: some View {
        Button(action: { isRecording.toggle() }) {
            HStack {
                if isRecording {
                    Text("Type shortcut...")
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
        .onKeyPress { keyPress in
            guard isRecording else { return .ignored }
            
            // Build modifier set
            var modifiers: Set<KeyboardShortcutConfig.ModifierKey> = []
            if keyPress.modifiers.contains(.command) { modifiers.insert(.command) }
            if keyPress.modifiers.contains(.shift) { modifiers.insert(.shift) }
            if keyPress.modifiers.contains(.option) { modifiers.insert(.option) }
            if keyPress.modifiers.contains(.control) { modifiers.insert(.control) }
            
            // Need at least one modifier
            guard !modifiers.isEmpty else {
                errorMessage = "Shortcut must include at least one modifier (⌘, ⇧, ⌥, or ⌃)"
                return .handled
            }
            
            // Get key code (simplified - in production use Carbon or similar)
            let keyCode = keyCharToCode(keyPress.characters)
            
            // Check if reserved
            if HotkeyService.isReservedShortcut(keyCode, modifiers: modifiers) {
                errorMessage = "This shortcut is reserved by the system"
                return .handled
            }
            
            // Update config
            config = KeyboardShortcutConfig(keyCode: keyCode, modifiers: modifiers)
            errorMessage = nil
            isRecording = false
            
            return .handled
        }
    }
    
    private func keyCharToCode(_ char: String) -> UInt32 {
        // Simplified mapping - in production use a more complete solution
        let charMap: [String: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47
        ]
        return charMap[char.lowercased()] ?? 47
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
                    Text("OpenAI API Key")
                        .font(.headline)
                    
                    Text("Required to use Keyboard Hero. Get your API key from platform.openai.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if showAPIKey {
                            TextField("sk-...", text: $appState.openAIApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $appState.openAIApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    if appState.openAIApiKey.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("API key required for corrections")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !appState.openAIApiKey.hasPrefix("sk-") {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("API key should start with 'sk-'")
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
                Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Keyboard Hero")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Fix typos and grammar mistakes instantly while preserving your writing style.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 8) {
                Link("Privacy Policy", destination: URL(string: "https://keyboardhero.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://keyboardhero.app/terms")!)
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
