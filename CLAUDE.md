# TypoFixr

macOS menu bar app that fixes typos/grammar while preserving writing style. Uses OpenAI GPT-4o-mini with auto-detected language.

## Tech Stack
- Swift 5.9+, SwiftUI, macOS 13.0+
- SQLite.swift (database), HotKey (global shortcuts)
- API key stored in Keychain

## Structure
```
Sources/TypoFixr/
├── TypoFixrApp.swift          # @main entry, Settings scene
├── AppDelegate.swift          # Menu bar, windows, state coordination
├── Models/
│   ├── AppState.swift         # Central app state, settings, rate limiting
│   └── Correction.swift       # Correction data model
├── Services/
│   ├── TextCorrectionService.swift  # Main correction flow (clipboard-based)
│   ├── OpenAIService.swift    # API calls to OpenAI
│   ├── HotkeyService.swift    # Global keyboard shortcut handling
│   ├── SecurityService.swift  # Sensitive data detection
│   ├── NetworkMonitor.swift   # Offline detection
│   └── HUDService.swift       # Floating notification display
├── Database/
│   └── DatabaseManager.swift  # SQLite storage for history/stats
└── Views/
    ├── MenuBarView.swift      # Popover menu content
    ├── SettingsView.swift     # Settings tabs
    ├── OnboardingView.swift   # First-launch setup
    └── HUDView.swift          # Floating notification view
```

## Key Behaviors

**Default Shortcut**: Cmd+Shift+D (keyCode 2), customizable in Settings

**Startup Flow**:
1. First launch → Only onboarding (no menu bar)
2. After "Get Started" → Menu bar icon + settings window
3. Subsequent launches → Menu bar only

**Text Selection** (Clipboard-based, works in all apps):
1. Existing selection (Cmd+C) → 2. Paragraph (Shift+Option+Up) → 3. Line (Shift+Cmd+Left) → 4. Prompt user

Text is always selected backward from cursor position, then copied via clipboard, corrected, and pasted back.

**Security**: Detects sensitive data (passwords, credit cards, SSNs) and prompt injection patterns before sending to API.

**Other**: Use ⌘Z to undo corrections, Launch at Login works via SMAppService

## Commands
```bash
swift build -c release                    # Build
swift test                                # Run tests
pkill -f "TypoFixr"; cp .build/release/TypoFixr ~/Applications/TypoFixr.app/Contents/MacOS/; codesign --force --deep --sign - ~/Applications/TypoFixr.app; open ~/Applications/TypoFixr.app  # Deploy

# Reset for testing
defaults write com.typofixr.app hasCompletedOnboarding -bool false
defaults delete com.typofixr.app keyboardShortcut
```

## Gotchas
- `NSApp.setActivationPolicy(.accessory)` must be called BEFORE `setupMenuBar()`
- Shortcut recorder uses `NSEvent.addLocalMonitorForEvents`, Escape cancels
- Settings window managed via `AppDelegate.showSettings()` (not SwiftUI selector)
- Windows (settings, onboarding) created manually in AppDelegate with fixed sizes
- Clipboard fallback delays: ~0.01-0.08s per operation (see timing constants in TextCorrectionService)
- Only select text BEFORE cursor (backward), never after
- Timer references must be stored and invalidated to prevent leaks

## AI Prompt Strategy
Fix only clear errors, use sentence context to disambiguate typos (e.g., "form" vs "from"), preserve tone/style, don't rephrase, keep informal language, preserve emojis/formatting, return ONLY corrected text.
