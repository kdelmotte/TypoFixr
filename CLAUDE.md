# TypoFixr development notes

## Git and verification

- Do not add `Co-Authored-By` trailers to commit messages.
- Follow `AGENTS.md`: after source or test changes, run `make build`, then `make deploy`, and report both results. Run the relevant tests before deployment. If the build fails, stop.
- Work in `kdelmotte/TypoFixr`. Preserve its app identity, storage paths, telemetry project, MIT licensing, and public download links.
- Unit tests are not proof of cross-app compatibility. Run real selection/copy/paste checks when changing the editing path, and record which editors were actually tested.

## Product and stack

macOS 13+ menu bar app, Swift 5.9+, SwiftUI/AppKit, SQLite.swift, HotKey, and TelemetryDeck. TypoFixr calls Groq-hosted `openai/gpt-oss-20b` directly using the user’s API key.

Identity constants live in `AppHelpers`: `TypoFixr`, bundle/defaults/Keychain service `com.typofixr.app`, and `TypoFixr/typo_fixr.db` under Application Support. Internal module and Xcode target names remain `TypoFixr`.

## Architecture

- `TextCorrectionService` runs on the main actor, takes injected correction/editor/feedback dependencies, and acquires `isProcessing` before its first suspension. Its `defer` ends the editor session and releases the gate on every exit.
- `ClipboardTextEditor` owns cross-app capture, revalidation, input monitoring, and replacement. `ClipboardTransaction` snapshots every available representation of every clipboard item and restores only while it still owns the clipboard.
- `GroqService` orchestrates requests through `ChatCompletionTransport`. `GroqClient` owns URLSession/HTTP handling and completion parsing. Cancellation propagates without becoming a generic network failure.
- `CorrectionPrompt`, `CorrectionChunker`, and `CorrectionOutputProcessor` keep prompt policy, splitting/reassembly, and output validation separate.
- `CredentialStore` is injectable. `KeychainStore` scopes every operation by service and account, updates existing items in place, and reports failures. For `groq_api_key` and `device_id`, preserve upgrades from pre-1.3.0 by reading only the exact empty-service legacy item, saving the scoped item first, and then deleting that exact legacy item. Never omit the service filter or import credentials from another app.
- `AppState` takes injected settings, database, and credentials. Tests use `TestEnvironment`; `AppRuntime` isolates the Xcode test host using `TYPOFIXR_TESTING=1`. Do not clear or query production persistence from tests.

## Editing contract

Default shortcut: **⌘⇧D**, customizable in Settings. Selection order:

1. Copy the existing selection with Cmd+C.
2. If no selected text is available, try Shift+Option+Up, then copy.
3. If that fails, try Shift+Cmd+Left, then copy.
4. Show a selection error if no text can be captured.

Fallbacks select backward from the cursor, not the entire field. The character limit is 5,000.

Accessibility permission is required to send commands, but an Accessibility text role, selected range, or selected-text value must **not** be required for compatibility. Codex and other web editors may support Copy/Paste without exposing that metadata. When AX explicitly reports an empty selection, skip the initial copy to avoid block-copy behavior in editors such as Notion.

The clipboard capture waits for delayed copy handlers, then restores the original clipboard before the network request. Before replacement, copy the selection again and compare it to the original raw capture. Use available AX identity/range/content comparisons as additional evidence. Input activity or a changed destination stops replacement. Only a fallback selection may be reselected, followed by another copy comparison; an explicit user selection is never reconstructed blindly.

Synthetic HID events include modifier `flagsChanged` events for Electron/Chromium compatibility and carry a marker so the input monitor can ignore the app's own commands. Keep clipboard restoration after paste long enough for the editor to consume it. Preserve later user clipboard changes.

Notes normalization applies only to single-line fallback captures. Keep raw capture text for verification; normalize known list artifacts only for correction input. Multi-line list structure and explicit selections are preserved.

No-change results do not send an arrow key or another editing command. Ordinary app undo handles replacements.

## Model and formatting contract

Requests use `temperature=0`, `top_p=1`, `n=1`, `reasoning_format=hidden`, and user-message instructions. Use `max_completion_tokens`, not `max_tokens`. Reasoning effort is low below 300 characters and medium otherwise. Token budgets use `max(floor, chars + overhead)` with floors 4096/16384 and overheads 2048/3072 for low/medium. HTTP timeout: 30 seconds. Requests are single-pass; HTTP 429 is reported as rate limiting.

A completion must finish with `stop`. Reject `length` even if the text looks complete or contains `__NO_CHANGES__`; never accept a potentially truncated replacement. Check the no-change marker before output sanitization. Identical output is also a valid no-change result.

Formatting cleanup must distinguish model-added wrappers from user-authored brackets, tags, quotes, list prefixes, and emoji joiners. Preserve boundary whitespace at replacement. Corrections within an apology must not be mistaken for a model refusal. Security checks can reject model-added dangerous content; sensitive-data and prompt-injection checks happen before API submission.

## Chunking

`CorrectionChunker` flattens all leaf chunks before API dispatch. `GroqService` runs one task group with at most ten requests in flight and reassembles results in source order. Do not add nested fan-out.

Splitting order: multi-line lists, paragraphs, sentences, then clauses. `chunkingThreshold` and `mediumReasoningThreshold` are 300; `maxClauseChunkSize` is 295. Small adjacent chunks can merge up to that limit. Clause delimiters are comma-space, semicolon-space, and space-dash-space, with a 40-character minimum fragment. Keep sentence gaps and list prefixes for exact reassembly. URL-healing prevents `NLTokenizer` splits inside URLs containing `?`.

## UI and persistence

- First launch shows onboarding; completion creates the menu bar and Settings. Later launches keep the menu bar and resume Accessibility or API Key setup if a prerequisite is missing. Use an explicit completion callback during recovery because the saved onboarding flag is already true.
- Call `NSApp.setActivationPolicy(.accessory)` before menu-bar setup. Every icon state must have a non-nil template image; use `TypoFixrBranding.menuBarImage` with its drawn fallback. Refresh process trust before opening the menu and before a correction.
- `AppDelegate` manages Settings/onboarding windows; shortcut recording uses a local event monitor and Escape cancels it.
- `HUDService.showLoading` stays visible until a result replaces it. Measure the text at a known width before attaching it to a reused window. Keep the HUD nonactivating, click-through, and visible while another app is active; guard delayed dismissals against hiding a newer presentation.
- The menu previews three corrections and opens full text in a detail popover. Bound its height to the visible screen and scroll overflow. Confirm history deletion. `SettingsSection` routes setup actions to the appropriate tab.
- Store/invalidate timers. `NWPathMonitor` must be recreated after cancellation.
- Recent in-memory history shows ten entries; the SQLite database retains history until cleared.
- The existing TelemetryDeck project is retained. App-defined signals contain categories and outcomes, not correction text or credentials. Tests skip telemetry initialization.

## Commands and release work

```bash
make build
make test
make deploy
make preflight-dmg
bash scripts/validate_release.sh v1.3.7
```

Deployment signs and verifies before replacing the installed app. It preserves onboarding and shortcuts. Use `TypoFixrDev` for development copies. Use the existing Developer ID for distribution builds; do not replace a working Developer ID app with a development identity. Stage safely using an explicit `APP_BUNDLE` and `LAUNCH_AFTER_DEPLOY=0`, which skips stopping/launching apps. Run signing jobs serially. Xcode is selected by the Makefile because Command Line Tools alone do not supply XCTest. Swift 6 toolchains need `--enable-xctest` for this suite.

See `RELEASING.md` for the release workflow, required secret names, and version checks. Do not claim Codex or another named editor passed merely because a synthetic native/WebKit test passed.
