---
description: Reset TypoFixr app to fresh-install state for onboarding testing
---

Reset TypoFixr to a fresh-install state so the onboarding flow can be tested from scratch.

Run ALL of the following steps in order:

1. **Quit TypoFixr** if it's running:
   ```
   osascript -e 'quit app "TypoFixr"' 2>/dev/null
   ```

2. **Clear all UserDefaults** for the app:
   ```
   defaults delete com.typofixr.app 2>/dev/null
   ```
   This removes: `hasCompletedOnboarding`, `keyboardShortcut`, and any other stored preferences.

3. **Keep the Keychain API key** — do NOT delete it. The Groq key at `com.typofixr.app` is preserved so onboarding detects and pre-fills it.

4. **Reset Accessibility permission**:
   ```
   tccutil reset Accessibility com.typofixr.app 2>/dev/null
   ```

5. **Confirm** the reset succeeded by verifying the onboarding flag is gone:
   ```
   defaults read com.typofixr.app hasCompletedOnboarding 2>&1
   ```
   This should print an error like "does not exist" — that means it worked.

6. Report what was done and remind me to relaunch via `make deploy` or Xcode to see the onboarding flow.
