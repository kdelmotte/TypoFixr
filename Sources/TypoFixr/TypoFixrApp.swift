import SwiftUI
import AppKit

@main
struct TypoFixrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if !AppRuntime.isRunningTests { TelemetryService.shared.initialize() }
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
