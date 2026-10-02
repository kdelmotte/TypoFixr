import SwiftUI
import AppKit

struct MenuBarView: View {
    static let width: CGFloat = 360
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    @State private var confirmsClearHistory = false
    var scrollsContent = true

    var body: some View {
        Group {
            if scrollsContent {
                ScrollView(.vertical) { content }
            } else {
                content.fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.width)
        .alert("Clear all local history?", isPresented: $confirmsClearHistory) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) { appState.clearHistory() }
        } message: {
            Text("This removes all saved corrections and usage counts on this Mac. Your API key and settings stay saved.")
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()
            history
            Divider()
            status
            Divider()
            actions
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TypoFixrMark(size: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(AppHelpers.productName).font(.system(size: 16, weight: .semibold))
                HStack(spacing: 7) {
                    Text("Correct text").font(.caption).foregroundColor(.secondary)
                    Text(appState.keyboardShortcut.displayString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        .help("Change this in Settings → Shortcut")
                }
            }
            Spacer(minLength: 0)
            if appState.isProcessing {
                ProgressView().controlSize(.small).accessibilityLabel("Correcting text")
            }
        }
        .padding(16)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent corrections").font(.caption.weight(.medium)).foregroundColor(.secondary)
                Spacer()
                if !appState.correctionHistory.isEmpty {
                    Button("Clear History…") { confirmsClearHistory = true }
                        .buttonStyle(.borderless).font(.caption)
                        .help("Clear all saved corrections and usage counts")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if appState.correctionHistory.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No corrections yet").font(.subheadline.weight(.medium))
                    Text("Press \(appState.keyboardShortcut.displayString) in a text field. Your recent fixes will appear here.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            } else {
                ForEach(appState.correctionHistory.prefix(3)) { correction in
                    CorrectionRow(correction: correction)
                }
            }
        }
        .padding(.bottom, 12)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.hasAccessibilityPermission {
                setupNotice(title: "Accessibility access needed", detail: "Allow TypoFixr in System Settings to correct text in your apps.", icon: "hand.raised.fill") {
                    Button("Open Accessibility Settings…") {
                        AppHelpers.requestAccessibilityPermission(source: .menuBar)
                    }
                }
            } else if !appState.hasValidApiKey {
                setupNotice(title: "Connect your Groq key", detail: "Add your API key to start correcting text.", icon: "key.fill") {
                    Button("Add API Key…") { SettingsSection.api.open() }
                }
            }

            if let error = appState.lastError,
               !(error == "Accessibility permission required" && !appState.hasAccessibilityPermission) {
                Label {
                    Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                }
            }

            let stats = appState.databaseManager.getStatistics()
            HStack(spacing: 10) {
                StatBadge(label: "Today", value: "\(stats.correctionsToday)")
                StatBadge(label: "This month", value: "\(stats.correctionsThisMonth)")
            }
        }
        .padding(16)
    }

    private func setupNotice<Action: View>(title: String, detail: String, icon: String,
                                          @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundColor(.orange)
            Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            action().buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 2) {
            MenuButton(title: "Settings…", systemImage: "gearshape", shortcut: "⌘,") { SettingsSection.general.open() }
                .keyboardShortcut(",", modifiers: .command)
            MenuButton(title: "Send Feedback", systemImage: "envelope") {
                let subject = "\(AppHelpers.productName) Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:\(AppHelpers.feedbackEmail)?subject=\(subject)") { openURL(url) }
            }
            Divider().padding(.vertical, 4)
            MenuButton(title: "Quit \(AppHelpers.productName)", systemImage: "power", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
    }
}

struct CorrectionRow: View {
    let correction: Correction
    @State private var isHovered = false
    @State private var showsDetail = false

    var body: some View {
        Button { showsDetail = true } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(correction.originalText).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(correction.timeAgo).font(.caption2).foregroundColor(.secondary).fixedSize()
                    }
                    Label {
                        Text(correction.correctedText).font(.system(size: 13)).foregroundColor(.primary).lineLimit(2)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right").font(.caption).foregroundColor(.accentColor)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help("View the full correction, copy text, or send feedback")
        .accessibilityLabel("View correction: \(correction.correctedText)")
        .onHover { isHovered = $0 }
        .popover(isPresented: $showsDetail, arrowEdge: .leading) {
            CorrectionDetailView(correction: correction)
        }
    }
}

struct CorrectionDetailView: View {
    let correction: Correction
    @Environment(\.openURL) private var openURL
    @State private var hasCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Correction").font(.headline)
                Spacer()
                Text(correction.timeAgo).font(.caption).foregroundColor(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    textBlock("Original", text: correction.originalText)
                    Divider()
                    textBlock("Corrected", text: correction.correctedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            Divider()
            HStack {
                Button(hasCopied ? "Copied" : "Copy corrected text") {
                    NSPasteboard.general.clearContents()
                    hasCopied = NSPasteboard.general.setString(correction.correctedText, forType: .string)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Send Feedback") { sendFeedback() }.buttonStyle(.borderless)
            }
        }
        .padding(18)
        .frame(width: 400)
    }

    private func textBlock(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sendFeedback() {
        let subject = "\(AppHelpers.productName) Correction Feedback"
        let body = "Original text:\n\(correction.originalText)\n\nCorrected text:\n\(correction.correctedText)\n\nWhat I expected instead:\n"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppHelpers.feedbackEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if let url = components.url { openURL(url) }
    }
}

struct MenuButton: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 20).foregroundColor(.secondary)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).font(.caption).foregroundColor(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
