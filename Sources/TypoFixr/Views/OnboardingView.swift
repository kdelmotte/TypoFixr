import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let layout: OnboardingWindowLayout

    @State private var currentStep: OnboardingStep = .welcome
    @State private var showAPIKey = false

    init(layout: OnboardingWindowLayout = .fallback) {
        self.layout = layout
    }

    private var snapshot: OnboardingContentSnapshot {
        OnboardingContentSnapshot(
            keyboardShortcutDisplayString: appState.keyboardShortcut.displayString,
            hasAccessibilityPermission: appState.hasAccessibilityPermission,
            apiKey: appState.groqApiKey,
            showsAPIKey: showAPIKey,
            usesCompactAccessibilityLayout: layout.usesCompactAccessibilityLayout
        )
    }

    private var gateState: OnboardingGateState {
        OnboardingGateState(
            hasAccessibilityPermission: appState.hasAccessibilityPermission,
            apiKeyValidationState: snapshot.apiKeyValidationState
        )
    }

    var body: some View {
        OnboardingShell(
            step: currentStep,
            snapshot: snapshot,
            apiKeyText: $appState.groqApiKey,
            primaryButtonTitle: currentStep.primaryButtonTitle(
                hasAccessibilityPermission: snapshot.hasAccessibilityPermission
            ),
            isPrimaryButtonDisabled: isPrimaryButtonDisabled,
            footerHint: currentStep.footerHint(
                hasAccessibilityPermission: snapshot.hasAccessibilityPermission
            ),
            onBack: currentStep.previous.map { previousStep in
                {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = previousStep
                    }
                }
            },
            onPrimaryAction: handlePrimaryAction,
            onToggleAPIKeyVisibility: { showAPIKey.toggle() },
            fillsWindowHeight: true
        )
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

    private func handlePrimaryAction() {
        switch currentStep {
        case .welcome:
            advance(to: .accessibility)
        case .accessibility:
            if appState.hasAccessibilityPermission {
                advance(to: .apiKey)
            } else {
                AppHelpers.requestAccessibilityPermission(source: .onboarding)
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
}

struct OnboardingShell: View {
    let step: OnboardingStep
    let snapshot: OnboardingContentSnapshot
    let apiKeyText: Binding<String>
    let primaryButtonTitle: String
    let isPrimaryButtonDisabled: Bool
    let footerHint: String
    let onBack: (() -> Void)?
    let onPrimaryAction: () -> Void
    let onToggleAPIKeyVisibility: () -> Void
    let fillsWindowHeight: Bool

    private var apiKeyValidationTint: Color {
        switch snapshot.apiKeyValidationState {
        case .empty:
            return .secondary
        case .invalidFormat:
            return .orange
        case .valid:
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if fillsWindowHeight {
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                contentArea
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            footer
        }
        .background(TypoFixrBrandPalette.secondaryCardFill)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                TypoFixrMark(size: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.progressLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(step.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(step.subtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            StepProgressIndicator(currentStep: step)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var contentArea: some View {
        VStack(spacing: 0) {
            stepContent
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if fillsWindowHeight {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
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

                    Label("Current shortcut: \(snapshot.keyboardShortcutDisplayString)", systemImage: "command.square")
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
    }

    private var accessibilityStep: some View {
        let sectionSpacing: CGFloat = snapshot.usesCompactAccessibilityLayout ? 14 : 18
        let cardSpacing: CGFloat = snapshot.usesCompactAccessibilityLayout ? 12 : 16
        let cardPadding: CGFloat = snapshot.usesCompactAccessibilityLayout ? 18 : 22

        return VStack(alignment: .leading, spacing: sectionSpacing) {
            OnboardingCard(spacing: 14, padding: cardPadding) {
                Text("Current status")
                    .font(.headline)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.hasAccessibilityPermission ? "Granted" : "Not granted yet")
                            .font(.title3.weight(.semibold))

                        Text(snapshot.hasAccessibilityPermission
                             ? "You’re ready to move on."
                             : "Open macOS Accessibility settings, enable TypoFixr, then come back here. We’ll detect the change automatically.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    PermissionStatusBadge(isGranted: snapshot.hasAccessibilityPermission)
                }

                if snapshot.usesCompactAccessibilityLayout && !snapshot.hasAccessibilityPermission {
                    Label("Tip: if TypoFixr already appears in the list, toggling it off and on again usually resolves stale permission state.", systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: cardSpacing) {
                OnboardingCard(padding: cardPadding) {
                    Text("What this unlocks")
                        .font(.headline)

                    OnboardingBulletRow(systemImage: "text.cursor", text: "Reads the text you selected when you trigger a fix.")
                    OnboardingBulletRow(systemImage: "arrow.left.arrow.right", text: "Replaces that same text with the corrected version.")
                    OnboardingBulletRow(systemImage: "hand.tap", text: "Only runs when you press your shortcut. Nothing is monitored in the background.")
                }

                OnboardingCard(padding: cardPadding) {
                    Text("How to grant access")
                        .font(.headline)

                    OnboardingStepRow(number: "1", text: "Click the button below to open the Accessibility panel.")
                    OnboardingStepRow(number: "2", text: "Find TypoFixr in the list and turn it on.")
                    OnboardingStepRow(number: "3", text: "Return here. The button will change to Continue once macOS reports permission.")
                }
            }

            if !snapshot.usesCompactAccessibilityLayout && !snapshot.hasAccessibilityPermission {
                Label("Tip: if TypoFixr already appears in the list, toggling it off and on again usually resolves stale permission state.", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingCard {
                Text("Paste your Groq API key")
                    .font(.headline)

                Text("Paste the full key from console.groq.com/keys. TypoFixr sends correction requests directly to Groq with your key. We do not proxy traffic or create an account for this version.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Group {
                        if snapshot.showsAPIKey {
                            TextField("Paste full API key", text: apiKeyText)
                        } else {
                            SecureField("Paste full API key", text: apiKeyText)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button(action: onToggleAPIKeyVisibility) {
                        Image(systemName: snapshot.showsAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(snapshot.showsAPIKey ? "Hide API key" : "Reveal API key")
                }

                InlineValidationRow(
                    systemImage: snapshot.apiKeyValidationState.iconSystemName,
                    tint: apiKeyValidationTint,
                    message: snapshot.apiKeyValidationState.message
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
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let onBack {
                Button("Back", action: onBack)
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

            Button(primaryButtonTitle, action: onPrimaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isPrimaryButtonDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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

                    Text(step.shortTitle)
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
