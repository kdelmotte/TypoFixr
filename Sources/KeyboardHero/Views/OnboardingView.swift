import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentPage) {
                WelcomePage()
                    .tag(0)

                PermissionPage(appState: appState)
                    .tag(1)

                APIKeyPage(appState: appState)
                    .tag(2)

                ReadyPage()
                    .environmentObject(appState)
                    .tag(3)
            }
            .tabViewStyle(.automatic)
            .frame(height: 380)
            
            // Navigation
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                if currentPage < 3 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                } else {
                    Button("Get Started") {
                        appState.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFinish)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 480)
    }
    
    private var canProceed: Bool {
        switch currentPage {
        case 1:
            return appState.hasAccessibilityPermission
        case 2:
            return !appState.openAIApiKey.isEmpty
        default:
            return true
        }
    }
    
    private var canFinish: Bool {
        return appState.hasAccessibilityPermission && !appState.openAIApiKey.isEmpty
    }
}

// MARK: - Welcome Page
struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "keyboard")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Welcome to Keyboard Hero")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Fix typos and grammar mistakes instantly\nwhile preserving your unique writing style.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "bolt.fill", text: "Fix text instantly with a keyboard shortcut")
                FeatureRow(icon: "person.fill", text: "Preserves your tone and style")
                FeatureRow(icon: "arrow.uturn.backward", text: "Easy undo if you prefer the original")
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Permission Page
struct PermissionPage: View {
    @ObservedObject var appState: AppState
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Accessibility Permission")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Keyboard Hero needs Accessibility permission to:")
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint(text: "Read text from the focused text field when you trigger a fix")
                    BulletPoint(text: "Replace the text with the corrected version")
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, 40)
            
            // Privacy assurance
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Privacy Commitment")
                        .fontWeight(.medium)
                }
                
                Text("We only access text when you press the keyboard shortcut. Text is sent to OpenAI for correction and immediately discarded. We do not store, log, or retain any of your text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Permission status and button
            VStack(spacing: 12) {
                if appState.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Permission Granted")
                            .foregroundColor(.green)
                    }
                    .font(.headline)
                } else {
                    Button(action: requestPermission) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open System Preferences")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 40)
                    
                    Text("Click the button above, then enable Keyboard Hero in the list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            startPermissionPolling()
        }
    }
    
    private func requestPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }
    
    private func startPermissionPolling() {
        guard !isChecking else { return }
        isChecking = true
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if trusted {
                timer.invalidate()
                isChecking = false
                DispatchQueue.main.async {
                    appState.hasAccessibilityPermission = true
                }
            }
        }
    }
}

// MARK: - API Key Page
struct APIKeyPage: View {
    @ObservedObject var appState: AppState
    @State private var showAPIKey = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("OpenAI API Key")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Keyboard Hero uses OpenAI to intelligently fix your text.\nYou'll need an API key to continue.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
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
                
                if !appState.openAIApiKey.isEmpty && appState.openAIApiKey.hasPrefix("sk-") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("API key looks valid")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 60)
            
            Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Get your API key from OpenAI")
                }
            }
            .font(.callout)
            
            // Cost estimate
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated Cost")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("~$0.50/month for typical usage (500 corrections)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Ready Page
struct ReadyPage: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Keyboard Hero is ready to help you fix typos.")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            // Quick guide
            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Guide")
                    .font(.headline)

                HowToRow(number: "1", text: "Type text in any app")
                HowToRow(number: "2", text: "Press \(appState.keyboardShortcut.displayString) to fix")
                HowToRow(number: "3", text: "Your text is instantly fixed!")

                Divider()

                HStack {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(.accentColor)
                    Text("Press the shortcut again within 3 seconds to undo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Helper Views
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

struct HowToRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
        }
    }
}

