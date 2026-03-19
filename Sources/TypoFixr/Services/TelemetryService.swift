import Foundation

#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

enum SettingsOpenSource: String {
    case menuBar = "menu_bar"
    case onboardingCompletion = "onboarding_completion"
}

enum AccessibilityGrantSource: String {
    case onboarding = "onboarding"
    case settings = "settings"
    case menuBar = "menu_bar"
}

enum SecurityWarningKind: String {
    case promptInjection = "prompt_injection"
    case sensitiveData = "sensitive_data"
}

enum CorrectionFailureReason: String {
    case accessibilityPermissionMissing = "accessibility_permission_missing"
    case offline = "offline"
    case noSelection = "no_selection"
    case selectionTooLong = "selection_too_long"
    case promptInjectionBlocked = "prompt_injection_blocked"
    case sensitiveDataCancelled = "sensitive_data_cancelled"
    case noApiKey = "no_api_key"
    case networkError = "network_error"
    case timeout = "timeout"
    case invalidResponse = "invalid_response"
    case apiError = "api_error"
    case rateLimited = "rate_limited"
    case suspiciousOutput = "suspicious_output"
    case outputTooLong = "output_too_long"
    case aiRefused = "ai_refused"
    case unexpected = "unexpected"

    init(apiError: GroqService.APIError) {
        switch apiError {
        case .noApiKey:
            self = .noApiKey
        case .networkError:
            self = .networkError
        case .timeout:
            self = .timeout
        case .invalidResponse:
            self = .invalidResponse
        case .apiError:
            self = .apiError
        case .rateLimited:
            self = .rateLimited
        case .suspiciousOutput:
            self = .suspiciousOutput
        case .outputTooLong:
            self = .outputTooLong
        case .aiRefused:
            self = .aiRefused
        }
    }
}

enum TelemetrySignal {
    struct Payload: Equatable {
        let name: String
        let parameters: [String: String]
    }

    case appLaunched
    case onboardingCompleted
    case settingsOpened(source: SettingsOpenSource)
    case accessibilityPermissionGranted(source: AccessibilityGrantSource)
    case shortcutChanged(isDefault: Bool)
    case securityWarningShown(kind: SecurityWarningKind)
    case correctionStarted
    case correctionSucceeded(selectionSource: TextCorrectionService.SelectionSource)
    case correctionNoChanges(selectionSource: TextCorrectionService.SelectionSource)
    case correctionFailed(reason: CorrectionFailureReason, selectionSource: TextCorrectionService.SelectionSource? = nil)

    var payload: Payload {
        switch self {
        case .appLaunched:
            return Payload(name: "App.launched", parameters: [:])
        case .onboardingCompleted:
            return Payload(name: "Onboarding.completed", parameters: [:])
        case .settingsOpened(let source):
            return Payload(
                name: "Settings.opened",
                parameters: ["source": source.rawValue]
            )
        case .accessibilityPermissionGranted(let source):
            return Payload(
                name: "Accessibility.permissionGranted",
                parameters: ["source": source.rawValue]
            )
        case .shortcutChanged(let isDefault):
            return Payload(
                name: "Shortcut.changed",
                parameters: ["is_default": isDefault ? "true" : "false"]
            )
        case .securityWarningShown(let kind):
            return Payload(
                name: "Security.warningShown",
                parameters: ["kind": kind.rawValue]
            )
        case .correctionStarted:
            return Payload(name: "Correction.started", parameters: [:])
        case .correctionSucceeded(let selectionSource):
            return Payload(
                name: "Correction.succeeded",
                parameters: ["selection_source": selectionSource.telemetryValue]
            )
        case .correctionNoChanges(let selectionSource):
            return Payload(
                name: "Correction.noChanges",
                parameters: ["selection_source": selectionSource.telemetryValue]
            )
        case .correctionFailed(let reason, let selectionSource):
            var parameters = ["reason": reason.rawValue]
            if let selectionSource {
                parameters["selection_source"] = selectionSource.telemetryValue
            }

            return Payload(name: "Correction.failed", parameters: parameters)
        }
    }
}

final class TelemetryService {
    static let shared = TelemetryService()

    private static let appID = "98B881E6-4BE0-4328-B0F5-45AC1BB14BD6"
    private var isInitialized = false

    private init() {}

    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true

        #if canImport(TelemetryDeck)
        let config = TelemetryDeck.Config(appID: Self.appID)
        TelemetryDeck.initialize(config: config)
        #endif
    }

    func track(_ signal: TelemetrySignal) {
        guard isInitialized else { return }

        #if canImport(TelemetryDeck)
        let payload = signal.payload
        if payload.parameters.isEmpty {
            TelemetryDeck.signal(payload.name)
        } else {
            TelemetryDeck.signal(payload.name, parameters: payload.parameters)
        }
        #endif
    }
}

private extension TextCorrectionService.SelectionSource {
    var telemetryValue: String {
        switch self {
        case .existingSelection:
            return "existing_selection"
        case .paragraphFallback:
            return "paragraph_fallback"
        case .lineFallback:
            return "line_fallback"
        }
    }
}
