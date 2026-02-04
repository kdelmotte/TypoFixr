# TypoFixr

macOS menu bar app that fixes typos/grammar while preserving writing style. Uses Groq-hosted OpenAI GPT-OSS 20B (`openai/gpt-oss-20b`) with auto-detected language.

## Tech Stack
- Swift 5.9+, SwiftUI, macOS 13.0+
- SQLite.swift (database), HotKey (global shortcuts)
- API key stored in Keychain with service scope `com.typofixr.app` (Groq keys start with `gsk_`; legacy unscoped items are auto-migrated)

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
│   ├── GroqService.swift       # API calls to Groq
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

**Rate Limiting**: Client-side rate limiting is checked before each correction attempt.

**Security**: Detects sensitive data (passwords, credit cards, SSNs) and prompt injection patterns before sending to API.

**Correction Reliability**: Deterministic decoding (`temperature=0`, `top_p=1`, `n=1`), explicit `__NO_CHANGES__` contract, dynamic `max_completion_tokens`, and a verification retry pass (`reasoning_effort=medium`) for empty/unchanged/length-capped outputs. Because GPT-OSS 20B is a reasoning model, hidden reasoning tokens consume part of the `max_completion_tokens` budget. The `evaluateAttempt` method is content-aware: it only retries on `finish_reason: "length"` when the visible output is genuinely truncated (<50% of input length); otherwise it accepts the correction.

**HUD Notifications**: Bottom-center placement on the active display under cursor, with horizontal safety clamping.

**Other**: Use ⌘Z to undo corrections, Launch at Login works via SMAppService.

## Commands
```bash
swift build -c debug                      # Fast local build
swift build -c release                    # Release build
swift test                                # Run tests
bash scripts/restart-onboarding.sh        # Restart app with onboarding forced
# Deploy (always reset to onboarding first)
defaults write com.typofixr.app hasCompletedOnboarding -bool false; defaults delete com.typofixr.app keyboardShortcut 2>/dev/null; pkill -f "TypoFixr"; cp .build/release/TypoFixr ~/Applications/TypoFixr.app/Contents/MacOS/; codesign --force --deep --sign - ~/Applications/TypoFixr.app; open ~/Applications/TypoFixr.app
```

## Gotchas
- `NSApp.setActivationPolicy(.accessory)` must be called BEFORE `setupMenuBar()`
- Shortcut recorder uses `NSEvent.addLocalMonitorForEvents`, Escape cancels
- Settings window managed via `AppDelegate.showSettings()` (not SwiftUI selector)
- Windows (settings, onboarding) created manually in AppDelegate with fixed sizes
- Clipboard fallback delays: ~0.01-0.08s per operation (see timing constants in TextCorrectionService)
- Only select text BEFORE cursor (backward), never after
- Timer references must be stored and invalidated to prevent leaks
- GPT-OSS requests must use `max_completion_tokens` (not `max_tokens`); reasoning tokens are hidden but count toward this budget
- Very long inputs (>= 4200 chars) use the large-token policy tier with one retry ceiling
- API timeout is 30 seconds (to accommodate reasoning model latency on long inputs)
- `NetworkMonitor` must cancel/recreate `NWPathMonitor` on restart (it cannot be restarted once cancelled)
- `NSApp.activate(ignoringOtherApps:)` is deprecated on macOS 14+; use availability check
- Shared helpers (`openAccessibilitySettings`, `feedbackEmail`) live in `AppHelpers` enum in AppState.swift
- `KeyboardShortcutConfig.keyCodeDisplayNames` is the single source of truth for key code → display string mapping
- `TextCorrectionService` uses `defer { appState.isProcessing = false }` — don't manually reset `isProcessing` in early returns

## AI Prompt Strategy
Fix only clear errors, use sentence context to disambiguate typos (e.g., "form" vs "from"), preserve tone/style, don't rephrase, keep informal language, preserve emojis/formatting, and return ONLY corrected text. If nothing needs correction, return `__NO_CHANGES__`.
