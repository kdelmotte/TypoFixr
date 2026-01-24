import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Recent Corrections
            if !appState.correctionHistory.isEmpty {
                recentCorrectionsSection
                Divider()
            }
            
            // Status Section
            statusSection
            
            Divider()
            
            // Actions
            actionsSection
        }
        .frame(width: 320)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            Image(systemName: "keyboard")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyboard Hero")
                    .font(.headline)
                
                Text("Press \(appState.keyboardShortcut.displayString) to fix text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if appState.isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding()
    }
    
    // MARK: - Recent Corrections
    private var recentCorrectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Corrections")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            
            ForEach(appState.correctionHistory.prefix(3)) { correction in
                CorrectionRow(correction: correction)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.hasAccessibilityPermission {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading) {
                        Text("Permission Required")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Grant Accessibility access to use")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Grant") {
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            if let error = appState.lastError {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            
            // Stats
            let stats = DatabaseManager.shared.getStatistics()
            HStack {
                StatBadge(label: "Today", value: "\(stats.correctionsToday)")
                StatBadge(label: "This Month", value: "\(stats.correctionsThisMonth)")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Actions
    private var actionsSection: some View {
        VStack(spacing: 0) {
            MenuButton(title: "Settings...", systemImage: "gear") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.showSettings()
                }
            }
            
            MenuButton(title: "Send Feedback", systemImage: "envelope") {
                if let url = URL(string: "mailto:feedback@keyboardhero.app?subject=Keyboard%20Hero%20Feedback") {
                    openURL(url)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            MenuButton(title: "Quit Keyboard Hero", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Correction Row
struct CorrectionRow: View {
    let correction: Correction
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(correction.truncatedOriginal)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.accentColor)

                        Text(correction.truncatedCorrected)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(correction.timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isHovered {
                        Button("Feedback") {
                            sendFeedback()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func sendFeedback() {
        let subject = "Keyboard Hero Correction Feedback"
        let body = """
        Original text:
        \(correction.originalText)

        Keyboard Hero changed it to:
        \(correction.correctedText)

        What I expected instead:
        [Please describe what you expected]

        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:feedback@keyboardhero.app?subject=\(encodedSubject)&body=\(encodedBody)") {
            openURL(url)
        }
    }
}

// MARK: - Menu Button
struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

