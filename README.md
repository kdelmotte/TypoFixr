# TypoFixr

A macOS menu bar app that fixes typos and grammar mistakes instantly while preserving your unique writing style.

## Features

- **Instant Corrections**: Press `⌘⇧D` (Command + Shift + D) to fix typos in any text field
- **Style Preservation**: AI fixes errors while keeping your tone and word choices
- **Smart Text Selection**: Automatically detects what to fix based on context
- **Easy Revert**: Press the shortcut again within 3 seconds to undo, or use the history menu
- **Works Everywhere**: Compatible with most macOS apps (Notes, Mail, Slack, Chrome, etc.)
- **Multi-language**: Supports 50+ languages with auto-detection

## Requirements

- macOS 13.0 (Ventura) or later
- OpenAI API key ([get one here](https://platform.openai.com/api-keys))

## Installation

### From Source

1. **Clone the repository**
   ```bash
   cd "TypoFixr"
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

2. **Add Your OpenAI API Key**
   - Click the menu bar icon > Settings > API
   - Enter your OpenAI API key

3. **Start Using**
   - Type text in any app
   - Press `⌘⇧.` to fix typos
   - That's it!

## Usage

### Basic Usage

1. Type text in any text field (Notes, Mail, Slack, etc.)
2. Press `⌘⇧.` (or your custom shortcut)
3. Your text is instantly corrected!

### Smart Text Selection

TypoFixr intelligently selects what to fix:

| Situation | Behavior |
|-----------|----------|
| Text is selected | Only selected text is sent for correction |
| Same field as last fix | Only text typed since last fix is sent |
| Text > 500 characters | You're prompted to select specific text |
| Otherwise | Entire text field is sent |

### Reverting Changes

- **Quick revert**: Press the shortcut again within 3 seconds
- **From history**: Click menu bar icon > Recent Corrections > Revert
- **System undo**: Use `⌘Z` in most apps

### Customization

Click the menu bar icon > Settings:

- **Shortcut**: Change the keyboard shortcut
- **Character Limit**: Adjust the max text length (300-1000)
- **Language**: Force a specific language or use auto-detect

## Privacy

- **User-triggered only**: Text is only accessed when you press the shortcut
- **Pass-through**: Text is sent to OpenAI, corrected, and immediately discarded
- **No storage**: We do not store, log, or retain any of your text
- **Local tracking**: Usage statistics are stored locally on your device only

## Development

### Project Structure

```
TypoFixr/
├── Package.swift              # Swift Package Manager config
├── Sources/
│   └── TypoFixr/
│       ├── TypoFixrApp.swift    # App entry point
│       ├── AppDelegate.swift        # Menu bar setup
│       ├── Models/
│       │   ├── AppState.swift       # App state management
│       │   ├── Correction.swift     # Correction model
│       │   └── CorrectionBookmark.swift
│       ├── Services/
│       │   ├── AccessibilityService.swift  # Text capture/replace
│       │   ├── OpenAIService.swift         # AI integration
│       │   ├── HotkeyService.swift         # Keyboard shortcuts
│       │   └── TextCorrectionService.swift # Main correction logic
│       ├── Database/
│       │   └── DatabaseManager.swift       # SQLite storage
│       ├── Views/
│       │   ├── MenuBarView.swift           # Dropdown menu
│       │   ├── SettingsView.swift          # Settings window
│       │   └── OnboardingView.swift        # First-run experience
│       └── Resources/
│           └── Info.plist
└── Tests/
    └── TypoFixrTests/
        ├── CorrectionTests.swift
        ├── CorrectionBookmarkTests.swift
        ├── AppStateTests.swift
        ├── KeyboardShortcutTests.swift
        └── CaptureStrategyTests.swift
```

### Running Tests

```bash
swift test
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

1. Verify your API key is correct in Settings > API
2. Check your OpenAI account has available credits
3. Ensure you have internet connectivity

## Cost Estimation

Using OpenAI's gpt-4o-mini model:
- ~$0.15 per 1M input tokens
- ~$0.60 per 1M output tokens
- **Typical usage**: ~$0.50/month for 500 corrections

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please read CONTRIBUTING.md for guidelines.

## Changelog

### v1.0.0
- Initial release
- Basic typo and grammar correction
- Smart text selection
- Revert functionality
- Multi-language support
