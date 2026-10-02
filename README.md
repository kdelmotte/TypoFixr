# TypoFixr

A macOS menu bar app that understands context and fixes your typos and grammar mistakes instantly, while preserving your unique writing style.

## Features

- **Instant Corrections**: Press `⌘⇧D` to fix typos in any text field
- **Style Preservation**: Fixes errors while keeping your tone, word choices, and formatting
- **Smart Text Selection**: Automatically selects text backward from cursor (paragraph → line → prompt)
- **Works Everywhere**: Compatible with most macOS apps (Notes, Mail, Slack, Chrome, etc.)
- **Handles Long Text**: Splits large text into sentences and corrects them in parallel for speed and reliability
- **List-Aware**: Bullet and numbered lists are corrected item-by-item, preserving structure
- **Multi-language**: Supports 50+ languages with auto-detection
- **Security**: Detects prompt injection attempts, warns about sensitive data, validates AI output
- **Local History**: Corrections are stored locally on your Mac and can be cleared anytime
- **Launch at Login**: Optionally start TypoFixr when you log in
- **Undo**: Use `⌘Z` in any app to revert a correction

## Requirements

- macOS 13.0 (Ventura) or later
- Groq API key ([get one here](https://console.groq.com/keys))

## Installation

### Download Latest Release

1. Visit the project site: [kdelmotte.github.io/TypoFixr](https://kdelmotte.github.io/TypoFixr/)
2. Or download the latest DMG directly: [TypoFixr.dmg](https://github.com/kdelmotte/TypoFixr/releases/latest/download/TypoFixr.dmg)
3. Open the DMG and drag TypoFixr to Applications
4. Launch TypoFixr and complete onboarding
5. Add your Groq API key when prompted

### From Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/kdelmotte/TypoFixr.git
   cd TypoFixr
   ```

2. **Build the app**
   ```bash
   make build      # Debug build
   make release    # Release build
   ```

3. **Deploy (build + sign + launch)**
   ```bash
   make deploy
   ```
   This builds a release binary, signs it with the local `TypoFixrDev` certificate (preserving accessibility permissions), preserves onboarding and shortcut settings, and launches the app.

## Setup

1. **Grant Accessibility Permission**
   - On first launch, you'll be prompted to grant Accessibility permission
   - Go to System Settings > Privacy & Security > Accessibility
   - Enable TypoFixr in the list

2. **Add Your Groq API Key**
   - Click the menu bar icon > Settings > API
   - Enter your Groq API key (starts with `gsk_`)

3. **Start Using**
   - Type text in any app
   - Press `⌘⇧D` to fix typos
   - That's it!

## Usage

### Basic Usage

1. Type text in any text field (Notes, Mail, Slack, etc.)
2. Press `⌘⇧D` (or your custom shortcut)
3. Your text is instantly corrected!

### Correction reliability

Copy and Paste remain the compatibility path. Editors do not need to expose an Accessibility text role or selected range, but macOS Accessibility permission is still required to send keyboard commands. Keep the destination field and selection unchanged while correction runs; user interaction or a changed destination stops replacement.

The app copies the selection again before replacing it, preserves available clipboard formats, and avoids restoring over a newer clipboard change. Repeated shortcuts cannot start overlapping corrections. Incomplete model responses are rejected instead of pasted. Select no more than 5,000 characters; use Cmd+Z in the destination app to undo.

### Smart Text Selection

TypoFixr intelligently selects what to fix using a clipboard-based approach:

| Priority | Behavior |
|----------|----------|
| 1. Selected text | If you've highlighted text, only that is corrected |
| 2. Paragraph | Selects backward from cursor to start of paragraph |
| 3. Line | If paragraph capture finds no text, selects backward to the start of the line |
| 4. Prompt | If no text found, you're prompted to select text |

### Customization

Click the menu bar icon > Settings:

| Tab | Options |
|-----|---------|
| **General** | Launch at Login |
| **Shortcut** | Change the trigger shortcut (default `⌘⇧D`) |
| **API** | Enter your Groq API key |
| **Security** | Toggle warnings and clear local history |
| **About** | Version info and feedback link |

## Security

TypoFixr scans text **before** sending it to Groq:
- **Prompt injection detection** — patterns like "ignore previous instructions"
- **Sensitive data warnings** — credit cards, SSNs, passwords, API keys, emails, phone numbers

For sensitive data, you can choose to proceed or cancel. Prompt-injection matches are blocked before an API request.

AI responses are **validated on return** for suspicious patterns (script tags, shell commands), AI refusals, and unexpected length.

## Privacy

- **User-triggered only**: Text is only accessed when you press the shortcut
- **Direct processing**: Selected text is sent directly from your Mac to Groq using your API key
- **Local storage**: Original and corrected text, source app identifiers, and token usage are stored in `~/Library/Application Support/TypoFixr/typo_fixr.db`. The menu shows the latest ten corrections; history persists until cleared.
- **Secure key storage**: Your API key is stored in macOS Keychain under `com.typofixr.app`. Legacy keys created before 1.3.0 migrate from the exact empty-service entry; other apps’ credentials are not imported or deleted.
- **Clear anytime**: Delete all history from Settings > Security
- **Telemetry**: Existing TelemetryDeck configuration is retained. App-defined event payloads report lifecycle and correction outcomes, without correction text or API keys; the SDK supplies its standard metadata.

## Development

### Project Structure

```
TypoFixr/
├── Package.swift                 # Swift Package Manager config
├── Sources/
│   └── TypoFixr/
│       ├── TypoFixrApp.swift     # App entry point
│       ├── AppDelegate.swift     # Menu bar setup
│       ├── Models/
│       │   ├── AppState.swift    # App state management
│       │   ├── Correction.swift  # Correction model
│       │   └── OnboardingFlow.swift  # Onboarding step/gating logic
│       ├── Services/
│       │   ├── TextCorrectionService.swift  # Main correction logic
│       │   ├── ClipboardTextEditor.swift     # Capture, revalidation, and clipboard restoration
│       │   ├── GroqService.swift             # Bounded request orchestration
│       │   ├── GroqClient.swift              # HTTP transport and response parsing
│       │   ├── CorrectionPrompt.swift       # Prompt and request policy
│       │   ├── CorrectionChunker.swift      # Split and reassemble text
│       │   ├── CorrectionOutputProcessor.swift # Completion and formatting validation
│       │   ├── CredentialStore.swift        # Scoped Keychain access
│       │   ├── HotkeyService.swift          # Keyboard shortcuts
│       │   ├── SecurityService.swift        # Security checks
│       │   ├── NetworkMonitor.swift         # Connectivity detection
│       │   └── HUDService.swift             # HUD notifications
│       ├── Database/
│       │   └── DatabaseManager.swift        # SQLite storage
│       ├── Assets.xcassets/                 # App icon and brand assets
│       └── Views/
│           ├── Branding.swift               # Shared TypoFixr branding
│           ├── MenuBarView.swift            # Dropdown menu
│           ├── SettingsView.swift           # Settings window
│           ├── OnboardingView.swift         # First-run experience
│           └── HUDView.swift                # HUD overlay
└── Tests/
    └── TypoFixrTests/
        ├── AppStateTests.swift
        ├── ClipboardTextEditorTests.swift
        ├── CredentialStoreTests.swift
        ├── GroqTransportTests.swift
        ├── TestEnvironment.swift
        ├── CorrectionTests.swift
        ├── KeyboardShortcutTests.swift
        ├── GroqPromptConfigurationTests.swift
        ├── GroqResponseParsingTests.swift
        ├── HUDServicePositioningTests.swift
        ├── SecurityServiceTests.swift
        ├── HUDViewTests.swift
        ├── WhitespaceNormalizationTests.swift
        ├── OnboardingFlowTests.swift
        ├── GroqOutputValidationTests.swift
        ├── TextCorrectionServiceTests.swift
        ├── SentenceChunkingTests.swift
        └── TextSelectionFlowTests.swift
```

### Running Tests

```bash
make test
```

Note: Requires Xcode (not just Command Line Tools) for XCTest support. The Makefile sets `DEVELOPER_DIR` automatically. Tests use temporary settings, in-memory databases and credentials, and named pasteboards. The Xcode test host skips normal app startup and telemetry. See [TEST_PLAN.md](TEST_PLAN.md) for automated coverage and app-specific manual checks.

### Dev Helper

Build, sign, preserve preferences, and launch:

```bash
make deploy
```

### Dependencies

- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - Database
- [HotKey](https://github.com/soffes/HotKey) - Global keyboard shortcuts
- [TelemetryDeck](https://github.com/TelemetryDeck/SwiftClient) - App lifecycle and correction outcome signals

## Troubleshooting

### "Permission Required" message

1. Open System Settings > Privacy & Security > Accessibility
2. Find TypoFixr in the list
3. Toggle it off and on again
4. Restart TypoFixr

### Shortcut not working

1. Check if another app is using the same shortcut
2. Try changing to a different shortcut in Settings

### Text not being replaced

1. Select the text before pressing the shortcut
2. Keep the destination field and selection unchanged until correction finishes
3. Check that the field accepts Copy/Paste and is not read-only

### API errors

1. Verify your API key is correct in Settings > API (should start with `gsk_`)
2. Check your Groq account is active
3. Ensure you have internet connectivity

### Security warnings

If you see warnings about sensitive data:
1. Review the flagged content
2. Choose "Send Anyway" if you're sure it's safe
3. Or "Cancel" to keep your original text

## Pricing

TypoFixr currently uses Groq-hosted OpenAI GPT-OSS 20B (`openai/gpt-oss-20b`).

Groq pricing and free-tier limits can change over time, so check your Groq dashboard for the current numbers.

For normal personal usage, Groq's free tier is likely enough, but TypoFixr does not add its own billing layer or markup.

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or pull request.

## Changelog

### v1.3.7
- Verify the copied selection before replacement and stop stale corrections after destination changes or user interaction
- Preserve clipboard items and representations, including rich text, images, and file URLs
- Keep clipboard compatibility when Accessibility selection metadata is absent; prevent overlapping corrections
- Reject truncated model responses; preserve user-authored brackets and emoji joiners; avoid false refusal detection for apology corrections
- Scope credential mutations and safely retain legacy upgrade behavior
- Isolate tests from real app data and preserve preferences during local deployment
- Separate correction transport, prompt policy, chunking, and output validation for focused testing

See [release notes](docs/releases/v1.3.7.md) and [RELEASING.md](RELEASING.md) for release preparation, signing, and validation.

### v1.3.6
- Replaced the custom DMG packaging path with a standard `appdmg` drag-and-drop installer flow
- Switched to static DMG background assets so the release and local preflight use the same fixed installer layout

### v1.3.5
- Rebuilt the DMG authoring path so Finder gets both background records instead of dropping the installer art
- Restored the installer background/arrow path without relying on flaky Finder automation

### v1.3.4
- Hardened DMG packaging so installer metadata no longer collides with stale mounted volumes
- Simplified the installer styling to a calmer, more reliable drag-to-Applications window

### v1.3.3
- Tightened the onboarding window sizing and spacing so the setup flow stays compact in the shipped app
- Cleaned up the DMG installer layout so Finder labels and icons no longer fight the background artwork

### v1.3.2
- Fixed the onboarding window layout so setup stays usable on smaller screens and the primary action remains reachable
- Fixed Accessibility permission refresh so onboarding, Settings, and the menu bar all detect restored access without polling forever

### v1.3.1
- Added TelemetryDeck analytics tracking for onboarding, settings, security warnings, and correction outcomes

### v1.3.0
- Switched to Groq-hosted OpenAI GPT-OSS 20B reasoning model for higher-quality corrections
- Long text is now split into sentences and corrected in parallel — faster and more reliable
- Bullet and numbered lists are corrected item-by-item, preserving list structure
- Boundary quotes and URLs are preserved through the correction pipeline
- Deterministic single-pass corrections with no retries
- Token budget scales automatically with input length
- Scoped Keychain storage with auto-migration of legacy API keys
- Branded app assets plus a more polished onboarding and settings experience
- Improved HUD notification positioning
- Various bug fixes and internal cleanup

### v1.2.1
- Improved contextual typo disambiguation (e.g., "note" vs "not")
- Deterministic decoding for consistent results on identical input

### v1.2.0
- Launch at Login via SMAppService
- Offline detection with network monitoring
- Code cleanup and bug fixes

### v1.1.0
- Security protections (prompt injection, sensitive data warnings)
- HUD notifications for correction status
- Output validation

### v1.0.0
- Initial release
