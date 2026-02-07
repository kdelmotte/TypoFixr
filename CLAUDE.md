# TypoFixr

## Git
- Do NOT add `Co-Authored-By` trailers to commit messages.

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

**Correction Reliability**: Single-pass, no retries. Deterministic decoding (`temperature=0`, `top_p=1`, `n=1`), explicit `__NO_CHANGES__` contract, and a linear `max_completion_tokens` formula: `max(floor, chars + overhead)`. Budget floor is 4096 (low) or 16384 (medium). Reasoning effort scales with input length: `low` for < 300 chars (pattern matching, sub-1s) and `medium` for >= 300 chars (deeper analysis, ~1-2s). Budget overhead is 2048 at `low` and 3072 at `medium` to absorb extra hidden reasoning tokens. Requests include `reasoning_format: "hidden"` so chain-of-thought stays internal and only corrected text appears in `content`. Instructions are placed in the user message (not system prompt) per Groq's recommendation for reasoning models. If output matches input without `__NO_CHANGES__` marker, the result is accepted as "no corrections needed" (not an error). The `resolveCorrection` method is content-aware: it errors on `finish_reason: "length"` only when visible output is genuinely truncated (<50% of input length); otherwise it accepts the correction. Chunking uses a **flatten-and-throttle** architecture: `flattenIntoLeafChunks` eagerly splits text into all leaf-level chunks (no API calls), then a single `TaskGroup` dispatches all leaves with `maxConcurrentChunks` (10) throttle — no nested fan-out. `reassembleFromLeafResults` reconstructs the full text bottom-up using a `ReassemblyPlan`. Splitting priority: list detection → paragraph splitting (with paragraph-level merging of small adjacent paragraphs when combined <= `maxClauseChunkSize`) → sentence chunking → single-call fallback. Max 10 concurrent API calls total (not per-level); adjacent sentences are aggressively merged when combined <= 295 chars (`maxClauseChunkSize`); URLs containing `?` are protected via `NSDataDetector` URL-healing merge. Oversized chunks (>295 chars, e.g. run-on sentences) are split at clause boundaries (`, `, `; `, ` - `) near the midpoint, with a 40-char minimum fragment to prevent tiny splits; this is recursive so all sub-chunks end up <= 295 chars. Comma/semicolon attaches to the left sub-chunk; the space becomes the gap for exact reassembly. If no clause delimiter is found, the chunk stays as-is (falls back to medium reasoning). Single-sentence long text with no clause delimiters falls back to single-call with medium reasoning. Multi-line list text (bullets or numbered) is detected before sentence chunking: each item's text is corrected independently without its prefix, then reassembled with original prefixes and gaps (blank lines between items). This prevents the model from duplicating list markers or restructuring numbered lists. List detection requires >=2 items of the same type (all bullets or all numbered); mixed types or partial lists fall through to normal correction. The `__NO_CHANGES__` marker is checked on raw API content BEFORE `sanitizeOutput` to prevent `normalizeLeadingListArtifacts` from prepending list prefixes that corrupt the marker (e.g. `"  - __NO_CHANGES__"` ≠ `"__NO_CHANGES__"`). Boundary quotes (`"`, `\u{201C}`, `\u{201D}`, `\u{00AB}`, `\u{00BB}`) are restored post-sanitization via `restoreBoundaryQuotes` — the model strips leading quotes when they appear adjacent to XML tags; single quotes excluded due to apostrophe overlap. Notes multi-line text skips bullet-prefix stripping in `normalizeCapturedTextForCorrection` so `parseMultiLineList` can detect and handle the list structure. Text containing `\n\n` paragraph breaks (>= 300 chars total) is split into paragraphs first via `splitIntoParagraphs`. Small adjacent paragraphs are merged when combined <= `maxClauseChunkSize` (295) — e.g. "thanks,\n\nKevin" becomes one chunk. Each paragraph independently goes through list detection, sentence chunking, or single-call correction — all as leaf chunks in the single flat dispatch. Pure lists still take the fast list path first; single-paragraph text falls through to sentence chunking unchanged.

**HUD Notifications**: Bottom-center placement on the active display under cursor, with horizontal safety clamping.

**Other**: Use ⌘Z to undo corrections, Launch at Login works via SMAppService.

## Commands
```bash
make build                                # Fast local build (debug)
make release                              # Release build
make test                                 # Run all tests (XCTest)
make deploy                               # Build release, reset onboarding, sign, launch
bash scripts/setup-signing.sh             # One-time: create TypoFixrDev signing cert
```

**Deploy always resets to onboarding** — this is intentional. After any code change, always `make deploy` (never just copy the binary manually). The Makefile sets `DEVELOPER_DIR` to Xcode and uses the `TypoFixrDev` certificate for stable signing.

## Gotchas
- `NSApp.setActivationPolicy(.accessory)` must be called BEFORE `setupMenuBar()`
- Shortcut recorder uses `NSEvent.addLocalMonitorForEvents`, Escape cancels
- Settings window managed via `AppDelegate.showSettings()` (not SwiftUI selector)
- Windows (settings, onboarding) created manually in AppDelegate with fixed sizes
- Clipboard fallback delays: ~0.01-0.08s per operation (see timing constants in TextCorrectionService)
- Only select text BEFORE cursor (backward), never after
- Timer references must be stored and invalidated to prevent leaks
- GPT-OSS requests must use `max_completion_tokens` (not `max_tokens`); reasoning tokens are hidden but count toward this budget
- Token budget uses linear formula: `max(floor, chars + overhead)` where floor is 4096 (low) or 16384 (medium), overhead is 2048 (low) or 3072 (medium reasoning effort, >= 300 chars)
- Groq defaults `reasoning_format` to `"raw"` which dumps `<think>` tags into visible output; always send `reasoning_format: "hidden"`
- Instructions go in user message (not system prompt) — Groq recommends avoiding system prompts for reasoning models
- API timeout is 30 seconds (tighter budgets keep latency well within this)
- `NetworkMonitor` must cancel/recreate `NWPathMonitor` on restart (it cannot be restarted once cancelled)
- `NSApp.activate(ignoringOtherApps:)` is deprecated on macOS 14+; use availability check
- Shared helpers (`openAccessibilitySettings`, `feedbackEmail`) live in `AppHelpers` enum in AppState.swift
- `KeyboardShortcutConfig.keyCodeDisplayNames` is the single source of truth for key code → display string mapping
- `TextCorrectionService` uses `defer { appState.isProcessing = false }` — don't manually reset `isProcessing` in early returns
- `xcode-select` points to Command Line Tools (no XCTest); Makefile sets `DEVELOPER_DIR` to Xcode for XCTest support
- Swift 6.x defaults to Swift Testing discovery; `--enable-xctest` flag required for XCTest-based tests
- App is signed with local `TypoFixrDev` certificate (not ad-hoc) to preserve accessibility permissions across deploys. Run `bash scripts/setup-signing.sh` once on a new machine
- Deploy (`make deploy`) always resets onboarding — don't skip this step
- `NLTokenizer` requires `import NaturalLanguage` (Apple framework, no package dependency)
- `chunkingThreshold` (300) must stay in sync with `mediumReasoningThreshold`
- `maxClauseChunkSize` (295) must stay below `mediumReasoningThreshold` (300) to ensure all chunks use low reasoning
- Clause delimiters (`, `, `; `, ` - `) split oversized chunks; comma/semicolon attaches to left, space becomes gap
- `minClauseFragment` (40) prevents clause splits from creating trivially small left fragments
- NLTokenizer splits URLs at `?` — URL-healing merge via `NSDataDetector` fixes this
- Sentence text is right-trimmed before API; trailing whitespace folded into gaps for exact reassembly
- `sanitizeOutput` strips ALL trailing whitespace (spaces, tabs, newlines, carriage returns) — model-added trailing `\n` are artifacts, not user content
- Multi-line list detection (`parseMultiLineList`) runs before sentence chunking; each item corrected without prefix to prevent model mangling list structure
- `normalizeLeadingListArtifacts` applies per-line when original and output have matching line counts; falls back to single-line otherwise
- `__NO_CHANGES__` marker must be checked on raw content BEFORE `sanitizeOutput` — list artifact normalization can prepend prefixes that corrupt the marker
- Notes single-line dash stripping is a known trade-off: can't distinguish "Notes bullet artifact" from "user-typed dash" for single-line text
- `restoreBoundaryQuotes` only handles double quotes and guillemets; single quotes (`'`) excluded due to apostrophe false positives on corrected contractions

## AI Prompt Strategy
Fix only clear errors, use sentence context to disambiguate typos (e.g., "form" vs "from"), preserve tone/style, don't rephrase, keep informal language, preserve emojis/formatting, and return ONLY corrected text. If nothing needs correction, return `__NO_CHANGES__`.
