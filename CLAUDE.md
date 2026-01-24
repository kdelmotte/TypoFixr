# Keyboard Hero

macOS menu bar app that fixes typos/grammar while preserving writing style. Uses OpenAI GPT-4o-mini with auto-detected language.

## Tech Stack
- Swift 5.9+, SwiftUI, macOS 13.0+
- SQLite.swift (database), HotKey (global shortcuts)
- API key stored in Keychain

## Structure
```
Sources/KeyboardHero/
├── KeyboardHeroApp.swift      # @main entry, Settings scene
├── AppDelegate.swift          # Menu bar, windows, state coordination
├── Models/                    # AppState, Correction, CorrectionBookmark
├── Services/                  # AccessibilityService, OpenAIService, HotkeyService, TextCorrectionService
├── Database/                  # DatabaseManager (SQLite)
└── Views/                     # MenuBarView, SettingsView, OnboardingView
```

## Key Behaviors

**Default Shortcut**: Cmd+Shift+D (keyCode 2), customizable in Settings

**Startup Flow**:
1. First launch → Only onboarding (no menu bar)
2. After "Get Started" → Menu bar icon + settings window
3. Subsequent launches → Menu bar only

**Text Selection** (Native apps via Accessibility API):
1. User's selection → 2. Bookmark (text since last fix) → 3. Current paragraph → 4. Full field

**Clipboard Fallback** (Chrome, Electron, Google Docs) - backward-only selection:
1. Existing selection (Cmd+C) → 2. Paragraph (Shift+Cmd+Up) → 3. Line (Shift+Cmd+Left) → 4. Prompt user

**Other**: 3-second revert window, "Feedback" button on history items opens email with original/corrected text

## Commands
```bash
swift build -c release                    # Build
pkill -f "KeyboardHero"; cp .build/release/KeyboardHero ~/Applications/KeyboardHero.app/Contents/MacOS/; codesign --force --deep --sign - ~/Applications/KeyboardHero.app; open ~/Applications/KeyboardHero.app  # Deploy

# Reset for testing
defaults write com.keyboardhero.app hasCompletedOnboarding -bool false
defaults delete com.keyboardhero.app keyboardShortcut
```

## Gotchas
- `NSApp.setActivationPolicy(.accessory)` must be called BEFORE `setupMenuBar()`
- Shortcut recorder uses `NSEvent.addLocalMonitorForEvents`, Escape cancels
- Settings window managed via `AppDelegate.showSettings()` (not SwiftUI selector)
- Windows (settings, onboarding) created manually in AppDelegate
- Clipboard fallback delays: ~0.05-0.08s per operation for speed
- Only select text BEFORE cursor (backward), never after

## AI Prompt Strategy
Fix only clear errors, preserve tone/style, don't rephrase, keep informal language, preserve emojis/formatting, return ONLY corrected text.
