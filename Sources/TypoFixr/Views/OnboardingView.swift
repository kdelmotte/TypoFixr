import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var currentStep: OnboardingStep = .welcome
    @State private var showAPIKey = false
    @State private var permissionTimer: Timer?
    @State private var isPollingPermission = false

    private var gateState: OnboardingGateState {
        OnboardingGateState(
            hasAccessibilityPermission: appState.hasAccessibilityPermission,
            apiKeyValidationState: GroqAPIKeyValidationState(apiKey: appState.groqApiKey)
        )
    }

    private var apiKeyValidationState: GroqAPIKeyValidationState {
        gateState.apiKeyValidationState
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content

            Divider()

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TypoFixrBrandPalette.secondaryCardFill)
        .onAppear {
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                TypoFixrMark(size: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentStep.progressLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(currentStep.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(currentStep.subtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            StepProgressIndicator(currentStep: currentStep)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .accessibility:
            accessibilityStep
        case .apiKey:
            apiKeyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How it works")
                        .font(.headline)

                    Text("TypoFixr waits in the menu bar until you trigger it, fixes the selected text, and pastes the result back where you were typing.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Current shortcut: \(appState.keyboardShortcut.displayString)", systemImage: "command.square")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(TypoFixrBrandPalette.blue.opacity(0.12))
                        .clipShape(Capsule())

                    OnboardingBulletRow(systemImage: "bolt.fill", text: "Runs from your current text field without disrupting your typing flow.")
                    OnboardingBulletRow(systemImage: "text.quote", text: "Corrects obvious mistakes while keeping tone, structure, and list formatting intact.")
                    OnboardingBulletRow(systemImage: "arrow.uturn.backward.circle.fill", text: "Standard undo works right away if you want the original text back.")
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingCard {
                Text("Current status")
                    .font(.headline)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appState.hasAccessibilityPermission ? "Granted" : "Not granted yet")
                            .font(.title3.weight(.semibold))

                        Text(appState.hasAccessibilityPermission
                             ? "You’re ready to move on."
                             : "Open macOS Accessibility settings, enable TypoFixr, then come back here. We’ll detect the change automatically.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    PermissionStatusBadge(isGranted: appState.hasAccessibilityPermission)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                OnboardingCard {
                    Text("What this unlocks")
                        .font(.headline)

                    OnboardingBulletRow(systemImage: "text.cursor", text: "Reads the text you selected when you trigger a fix.")
                    OnboardingBulletRow(systemImage: "arrow.left.arrow.right", text: "Replaces that same text with the corrected version.")
                    OnboardingBulletRow(systemImage: "hand.tap", text: "Only runs when you press your shortcut. Nothing is monitored in the background.")
                }

                OnboardingCard {
                    Text("How to grant access")
                        .font(.headline)

                    OnboardingStepRow(number: "1", text: "Click the button below to open the Accessibility panel.")
                    OnboardingStepRow(number: "2", text: "Find TypoFixr in the list and turn it on.")
                    OnboardingStepRow(number: "3", text: "Return here. The button will change to Continue once macOS reports permission.")
                }
            }

            if !appState.hasAccessibilityPermission {
                Label("Tip: if TypoFixr already appears in the list, toggling it off and on again usually resolves stale permission state.", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingCard {
                Text("Paste your Groq API key")
                    .font(.headline)

                Text("Paste the full key from console.groq.com/keys. TypoFixr sends correction requests directly to Groq with your key. We do not proxy traffic or create an account for this version.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Group {
                        if showAPIKey {
                            TextField("Paste full API key", text: $appState.groqApiKey)
                        } else {
                            SecureField("Paste full API key", text: $appState.groqApiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showAPIKey ? "Hide API key" : "Reveal API key")
                }

                InlineValidationRow(
                    systemImage: apiKeyValidationState.iconSystemName,
                    tint: apiKeyValidationTint,
                    message: apiKeyValidationState.message
                )

                if let groqURL = URL(string: "https://console.groq.com/keys") {
                    Link(destination: groqURL) {
                        Label("Open Groq key dashboard", systemImage: "arrow.up.right.square")
                            .font(.callout.weight(.medium))
                    }
                }
            }

            OnboardingCard {
                Text("Privacy")
                    .font(.headline)

                OnboardingBulletRow(systemImage: "key.fill", text: "Your API key is stored locally in macOS Keychain on this Mac.")
                OnboardingBulletRow(systemImage: "lock.shield", text: "TypoFixr only reads text when you trigger a correction.")
                OnboardingBulletRow(systemImage: "network", text: "Requests go straight to Groq from your device using your account.")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let previousStep = currentStep.previous {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = previousStep
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }

            Spacer()

            Text(footerHint)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(primaryButtonTitle, action: handlePrimaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isPrimaryButtonDisabled)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .welcome:
            return "Continue"
        case .accessibility:
            return appState.hasAccessibilityPermission ? "Continue" : "Open Accessibility Settings"
        case .apiKey:
            return "Finish Setup"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        switch currentStep {
        case .welcome:
            return false
        case .accessibility:
            return false
        case .apiKey:
            return !gateState.canContinue(from: .apiKey)
        }
    }

    private var footerHint: String {
        switch currentStep {
        case .welcome:
            return "Setup takes about a minute."
        case .accessibility:
            return appState.hasAccessibilityPermission
                ? "Accessibility is ready."
                : "We’ll keep checking while this window stays open."
        case .apiKey:
            return "Your key stays local in Keychain."
        }
    }

    private var apiKeyValidationTint: Color {
        switch apiKeyValidationState {
        case .empty:
            return .secondary
        case .invalidFormat:
            return .orange
        case .valid:
            return .green
        }
    }

    private func handlePrimaryAction() {
        switch currentStep {
        case .welcome:
            advance(to: .accessibility)
        case .accessibility:
            if appState.hasAccessibilityPermission {
                advance(to: .apiKey)
            } else {
                AppHelpers.openAccessibilitySettings()
                startPermissionPolling()
            }
        case .apiKey:
            guard gateState.canContinue(from: .apiKey) else { return }
            appState.hasCompletedOnboarding = true
            dismiss()
        }
    }

    private func advance(to step: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = step
        }
    }

    private func startPermissionPolling() {
        guard !isPollingPermission else { return }
        isPollingPermission = true

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            let wasTrusted = appState.hasAccessibilityPermission

            DispatchQueue.main.async {
                if trusted && !wasTrusted {
                    TelemetryService.shared.track(.accessibilityPermissionGranted(source: .onboarding))
                }
                appState.hasAccessibilityPermission = trusted
            }

            if trusted {
                timer.invalidate()
                permissionTimer = nil
                isPollingPermission = false
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        isPollingPermission = false
    }
}

struct StepProgressIndicator: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases) { step in
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(fillColor(for: step))
                        .frame(height: 8)
                        .overlay(
                            Capsule()
                                .stroke(TypoFixrBrandPalette.softBorder, lineWidth: step == currentStep ? 0 : 1)
                        )

                    Text(shortTitle(for: step))
                        .font(.caption)
                        .foregroundColor(step == currentStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fillColor(for step: OnboardingStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return TypoFixrBrandPalette.green
        }
        if step == currentStep {
            return TypoFixrBrandPalette.blue
        }
        return Color.secondary.opacity(0.18)
    }

    private func shortTitle(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:
            return "Welcome"
        case .accessibility:
            return "Accessibility"
        case .apiKey:
            return "Groq Key"
        }
    }
}

struct OnboardingBulletRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(TypoFixrBrandPalette.blue)
                .frame(width: 18)

            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingStepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(TypoFixrBrandPalette.blue)
                .clipShape(Circle())

            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PermissionStatusBadge: View {
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "hand.raised.fill")
            Text(isGranted ? "Granted" : "Waiting")
                .fontWeight(.semibold)
        }
        .font(.callout)
        .foregroundColor(isGranted ? .green : .orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((isGranted ? Color.green : Color.orange).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct InlineValidationRow: View {
    let systemImage: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(tint)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
