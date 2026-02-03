# TypoFixr

A macOS menu bar app that understands context and fixes your typos and grammar mistakes instantly, while preserving your unique writing style.

## Features

- **Instant Corrections**: Press `⌘⇧D` (Command + Shift + D) to fix typos in any text field
- **Style Preservation**: AI fixes errors while keeping your tone and word choices
- **Smart Text Selection**: Automatically selects text backward from cursor (paragraph → line → prompt)
- **Works Everywhere**: Compatible with most macOS apps (Notes, Mail, Slack, Chrome, etc.)
- **Multi-language**: Supports 50+ languages with auto-detection
- **Security Protections**: Detects prompt injection attempts and warns about sensitive data
- **Offline Detection**: Shows status when network is unavailable
- **Rate Limiting**: Configurable limits to prevent accidental overuse
- **Spending Cap**: Set monthly token limits to control API costs
- **Launch at Login**: Optionally start TypoFixr when you log in

## Requirements

- macOS 13.0 (Ventura) or later
- Groq API key ([get one here](https://console.groq.com/keys))

## Installation

### From Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/kdelmotte/TypoFixr.git
   cd TypoFixr
   ```

2. **Build the app**
   ```bash
   swift build -c release
   ```

3. **Run the app**
   ```bash
   .build/release/TypoFixr
   ```

### Using Xcode

1. Open the project folder in Xcode
2. Select Product > Build
3. Run the app

## Setup

1. **Grant Accessibility Permission**
   - On first launch, you'll be prompted to grant Accessibility permission
   - Go to System Preferences > Privacy & Security > Accessibility
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

### Smart Text Selection

TypoFixr intelligently selects what to fix using a clipboard-based approach:

| Priority | Behavior |
|----------|----------|
| 1. Selected text | If you've highlighted text, only that is corrected |
| 2. Paragraph | Selects backward from cursor to start of paragraph |
| 3. Line | If paragraph is too long, selects current line instead |
| 4. Prompt | If no text found, you're prompted to select text |

### Reverting Changes

- **System undo**: Use `⌘Z` in any app to undo the correction

### Customization

Click the menu bar icon > Settings:

**General Tab:**
- **Character Limit**: Adjust the max text length (300-1000, default 1000)
- **Launch at Login**: Start TypoFixr when you log in

**Shortcut Tab:**
- **Keyboard Shortcut**: Change the trigger shortcut (default `⌘⇧D`)

**API Tab:**
- **API Key**: Enter your Groq API key

**Security Tab:**
- **Security Warnings**: Toggle warnings for sensitive data and prompt injections
- **Rate Limiting**: Set max corrections per minute (5-30) and per hour (20-500)
- **Spending Cap**: Enable and set monthly token limits
- **Clear History**: Remove all correction history

## Security

TypoFixr includes multiple layers of security:

### Pre-flight Checks
Before sending text to Groq, TypoFixr scans for:
- **Prompt Injection Attempts**: Detects patterns like "ignore previous instructions"
- **Sensitive Data**: Warns about credit card numbers, SSNs, passwords, API keys, emails, and phone numbers

When detected, you'll see a warning and can choose to proceed or cancel.

### Output Validation
AI responses are validated for:
- **Suspicious Patterns**: Script tags, shell commands, JavaScript URLs
- **AI Refusals**: Detects when the AI declines to process text
- **Length Limits**: Blocks unexpectedly long responses
- **Similarity Checks**: Ensures output is similar to input (typo fixes, not rewrites)

### Rate Limiting
Prevents accidental overuse with configurable limits:
- Per-minute limits (default: 15)
- Per-hour limits (default: 100)
- Monthly token spending cap (optional)

## Privacy

- **User-triggered only**: Text is only accessed when you press the shortcut
- **Pass-through**: Text is sent to Groq, corrected, and immediately discarded
- **Local storage**: Correction history is stored locally in SQLite
- **Secure key storage**: Your API key is stored in macOS Keychain
- **Clear anytime**: Delete all history from Settings > Security

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
│       │   └── Correction.swift  # Correction model
│       ├── Services/
│       │   ├── TextCorrectionService.swift  # Main correction logic
│       │   ├── GroqService.swift             # AI integration
│       │   ├── HotkeyService.swift          # Keyboard shortcuts
│       │   ├── SecurityService.swift        # Security checks
│       │   ├── NetworkMonitor.swift         # Connectivity detection
│       │   └── HUDService.swift             # HUD notifications
│       ├── Database/
│       │   └── DatabaseManager.swift        # SQLite storage
│       └── Views/
│           ├── MenuBarView.swift            # Dropdown menu
│           ├── SettingsView.swift           # Settings window
│           ├── OnboardingView.swift         # First-run experience
│           └── HUDView.swift                # HUD overlay
└── Tests/
    └── TypoFixrTests/
        ├── AppStateTests.swift
        ├── CorrectionTests.swift
        ├── KeyboardShortcutTests.swift
        ├── SecurityTests.swift
        ├── HUDViewTests.swift
        └── WhitespaceNormalizationTests.swift
```

### Running Tests

```bash
swift test
```

Note: Requires Xcode (not just Command Line Tools) for XCTest support.

### Dev Helper

Restart TypoFixr and force onboarding to appear again:

```bash
bash scripts/restart-onboarding.sh
```

### Dependencies

- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - Database
- [HotKey](https://github.com/soffes/HotKey) - Global keyboard shortcuts

## Troubleshooting

### "Permission Required" message

1. Open System Preferences > Privacy & Security > Accessibility
2. Find TypoFixr in the list
3. Toggle it off and on again
4. Restart TypoFixr

### Shortcut not working

1. Check if another app is using the same shortcut
2. Try changing to a different shortcut in Settings

### Text not being replaced

1. Some apps have limited accessibility support
2. Try selecting the text before pressing the shortcut
3. Check if the text field is read-only

### API errors

1. Verify your API key is correct in Settings > API (should start with `gsk_`)
2. Check your Groq account is active
3. Ensure you have internet connectivity

### "Response differed too much" error

This happens when the AI returns something very different from your input. This is a security feature. Try:
1. Selecting a smaller portion of text
2. Checking if your text contains unusual formatting

### Security warnings

If you see warnings about sensitive data:
1. Review the flagged content
2. Choose "Send Anyway" if you're sure it's safe
3. Or "Cancel" to keep your original text

## Cost Estimation

Using Groq's llama-3.1-8b-instant model:
- ~$0.05 per 1M input tokens
- ~$0.08 per 1M output tokens
- **Typical usage**: ~$0.01/month for 500 corrections (essentially free)

Use the **Spending Cap** feature in Settings > Security to set monthly limits and monitor usage.

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or pull request.

## Changelog

### v1.2.1
- Improved contextual typo disambiguation in system prompt (better handling of garbled tokens like note/not)
- Switched Groq request decoding to deterministic settings (`temperature=0`, `top_p=1`, `n=1`) for identical-input consistency
- Added prompt version traceability (`v2-contextual-deterministic`) in debug logs
- Added unit tests for prompt contract and deterministic request configuration

### v1.2.0
- Removed unused code (encryption, accessibility capture, bookmarks)
- Implemented Launch at Login properly with SMAppService
- Added offline detection with network monitoring
- Fixed timer leaks in permission polling
- Improved code organization and documentation

### v1.1.0
- Added security protections (prompt injection detection, sensitive data warnings)
- Added rate limiting (per-minute, per-hour, monthly token limits)
- Added output validation (similarity checks, suspicious pattern detection)
- Added HUD notifications for correction status
- Improved character-level similarity algorithm for better typo detection
- Fixed false positives in AI refusal detection for contractions
- Default character limit increased to 1000

### v1.0.0
- Initial release
- Basic typo and grammar correction
- Smart text selection
- Multi-language support
