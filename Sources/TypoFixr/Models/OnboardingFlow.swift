import Foundation

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

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}

enum GroqAPIKeyValidationState: Equatable {
    case empty
    case invalidFormat
    case valid

    init(apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedKey.isEmpty {
            self = .empty
        } else if trimmedKey.hasPrefix("gsk_") {
            self = .valid
        } else {
            self = .invalidFormat
        }
    }

    var message: String {
        switch self {
        case .empty:
            return "Paste a Groq API key to finish setup."
        case .invalidFormat:
            return "Groq API keys should start with \"gsk_\"."
        case .valid:
            return "Key format looks valid."
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
