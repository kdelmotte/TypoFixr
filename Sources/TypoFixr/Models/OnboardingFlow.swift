import Foundation
import CoreGraphics

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case accessibility
    case apiKey

    var id: Int { rawValue }

    var number: Int {
        rawValue + 1
    }

    var title: String {
        switch self {
        case .welcome:
            return "Fix selected text without leaving your app"
        case .accessibility:
            return "Give TypoFixr permission to help"
        case .apiKey:
            return "Connect your Groq API key"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Use your shortcut to clean up the text you selected and paste the result back in place."
        case .accessibility:
            return "Accessibility access lets TypoFixr read the text you select and paste the corrected version back in place."
        case .apiKey:
            return "Your Groq key stays on this Mac and is used for direct requests to Groq when you trigger a correction."
        }
    }

    var progressLabel: String {
        "Step \(number) of \(Self.allCases.count)"
    }

    var shortTitle: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .accessibility:
            return "Accessibility"
        case .apiKey:
            return "Groq Key"
        }
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    func primaryButtonTitle(hasAccessibilityPermission: Bool) -> String {
        switch self {
        case .welcome:
            return "Continue"
        case .accessibility:
            return hasAccessibilityPermission ? "Continue" : "Open Accessibility Settings"
        case .apiKey:
            return "Finish Setup"
        }
    }

    func footerHint(hasAccessibilityPermission: Bool) -> String {
        switch self {
        case .welcome:
            return "Setup takes about a minute."
        case .accessibility:
            return hasAccessibilityPermission
                ? "Accessibility is ready."
                : "We’ll keep checking while this window stays open."
        case .apiKey:
            return "Your key stays local in Keychain."
        }
    }
}

struct OnboardingContentSnapshot: Equatable {
    let keyboardShortcutDisplayString: String
    let hasAccessibilityPermission: Bool
    let apiKey: String
    let showsAPIKey: Bool
    let usesCompactAccessibilityLayout: Bool

    var apiKeyValidationState: GroqAPIKeyValidationState {
        GroqAPIKeyValidationState(apiKey: apiKey)
    }

    static func measurement(
        for step: OnboardingStep,
        usesCompactAccessibilityLayout: Bool
    ) -> OnboardingContentSnapshot {
        switch step {
        case .welcome:
            return OnboardingContentSnapshot(
                keyboardShortcutDisplayString: KeyboardShortcutConfig.defaultConfig.displayString,
                hasAccessibilityPermission: false,
                apiKey: "",
                showsAPIKey: false,
                usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
            )
        case .accessibility:
            return OnboardingContentSnapshot(
                keyboardShortcutDisplayString: KeyboardShortcutConfig.defaultConfig.displayString,
                hasAccessibilityPermission: false,
                apiKey: "",
                showsAPIKey: false,
                usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
            )
        case .apiKey:
            return OnboardingContentSnapshot(
                keyboardShortcutDisplayString: KeyboardShortcutConfig.defaultConfig.displayString,
                hasAccessibilityPermission: false,
                apiKey: "",
                showsAPIKey: false,
                usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
            )
        }
    }
}

struct OnboardingWindowLayout: Equatable {
    let size: CGSize
    let usesCompactAccessibilityLayout: Bool

    static let fallback = OnboardingWindowLayout(
        size: CGSize(width: 640, height: 560),
        usesCompactAccessibilityLayout: false
    )
}

enum OnboardingWindowSizer {
    static let preferredWidth: CGFloat = 640
    static let fallbackWidth: CGFloat = 680
    static let screenMargin: CGFloat = 80

    static func resolveLayout(
        for visibleFrame: CGRect,
        measureHeight: (OnboardingStep, CGFloat, Bool) -> CGFloat
    ) -> OnboardingWindowLayout {
        let maxAllowedWidth = max(0, visibleFrame.width - screenMargin)
        let maxAllowedHeight = max(0, visibleFrame.height - screenMargin)

        guard maxAllowedWidth > 0, maxAllowedHeight > 0 else {
            return .fallback
        }

        let preferredMeasuredWidth = min(preferredWidth, maxAllowedWidth)
        let preferredLayout = measuredLayout(
            width: preferredMeasuredWidth,
            usesCompactAccessibilityLayout: false,
            measureHeight: measureHeight
        )

        if preferredLayout.size.height <= maxAllowedHeight {
            return preferredLayout
        }

        let widenedMeasuredWidth = min(fallbackWidth, maxAllowedWidth)
        if widenedMeasuredWidth > preferredMeasuredWidth {
            let widenedLayout = measuredLayout(
                width: widenedMeasuredWidth,
                usesCompactAccessibilityLayout: false,
                measureHeight: measureHeight
            )

            if widenedLayout.size.height <= maxAllowedHeight {
                return widenedLayout
            }
        }

        return measuredLayout(
            width: max(widenedMeasuredWidth, preferredMeasuredWidth),
            usesCompactAccessibilityLayout: true,
            measureHeight: measureHeight
        )
    }

    private static func measuredLayout(
        width: CGFloat,
        usesCompactAccessibilityLayout: Bool,
        measureHeight: (OnboardingStep, CGFloat, Bool) -> CGFloat
    ) -> OnboardingWindowLayout {
        let height = ceil(
            OnboardingStep.allCases
                .map { measureHeight($0, width, usesCompactAccessibilityLayout) }
                .max() ?? OnboardingWindowLayout.fallback.size.height
        )

        return OnboardingWindowLayout(
            size: CGSize(width: width, height: height),
            usesCompactAccessibilityLayout: usesCompactAccessibilityLayout
        )
    }
}

enum GroqAPIKeyValidationState: Equatable {
    case empty
    case invalidFormat
    case valid

    private static let obviousExampleKeys: Set<String> = [
        "gsk_...",
        "gsk_test_key"
    ]

    static func trimmed(_ apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isObviousExample(_ apiKey: String) -> Bool {
        obviousExampleKeys.contains(trimmed(apiKey))
    }

    static func isValidGroqAPIKey(_ apiKey: String) -> Bool {
        let trimmedKey = trimmed(apiKey)

        guard !trimmedKey.isEmpty else { return false }
        guard !isObviousExample(trimmedKey) else { return false }
        guard !trimmedKey.contains(where: \.isWhitespace) else { return false }

        return trimmedKey.hasPrefix("gsk_") && trimmedKey.count > 12
    }

    static func sanitizedPersistedAPIKey(_ apiKey: String?) -> String {
        guard let apiKey else { return "" }

        let trimmedKey = trimmed(apiKey)
        guard !isObviousExample(trimmedKey) else { return "" }

        return trimmedKey
    }

    init(apiKey: String) {
        let trimmedKey = Self.trimmed(apiKey)

        if trimmedKey.isEmpty {
            self = .empty
        } else if Self.isValidGroqAPIKey(trimmedKey) {
            self = .valid
        } else {
            self = .invalidFormat
        }
    }

    var message: String {
        switch self {
        case .empty:
            return "Paste your full Groq API key to finish setup."
        case .invalidFormat:
            return "Paste the full key from console.groq.com/keys, including the prefix."
        case .valid:
            return "Full key format looks valid."
        }
    }

    var iconSystemName: String {
        switch self {
        case .empty:
            return "info.circle.fill"
        case .invalidFormat:
            return "exclamationmark.triangle.fill"
        case .valid:
            return "checkmark.circle.fill"
        }
    }
}

struct OnboardingGateState {
    let hasAccessibilityPermission: Bool
    let apiKeyValidationState: GroqAPIKeyValidationState

    func canContinue(from step: OnboardingStep) -> Bool {
        switch step {
        case .welcome:
            return true
        case .accessibility:
            return hasAccessibilityPermission
        case .apiKey:
            return apiKeyValidationState == .valid
        }
    }
}
