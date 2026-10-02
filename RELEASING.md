# Releasing TypoFixr

Use `kdelmotte/TypoFixr`, its existing app identity `com.typofixr.app`, and the asset name `TypoFixr.dmg`. Keep the website and README’s public download links compatible.

## Version and verification

Update the version/build in `Sources/TypoFixr/Info.plist` and every Xcode app/test configuration. Version 1.3.7 uses build 4. Add notes at `docs/releases/v<version>.md`, update the README changelog and test plan, and run:

```bash
bash scripts/validate_release.sh v1.3.7
make build
make test
make deploy
```

`make deploy` builds and verifies before replacing `~/Applications/TypoFixr.app`, signs with `TypoFixrDev`, and preserves onboarding and shortcuts. `make preflight-dmg` checks the local installer flow with the same preferences. Development builds are not distribution artifacts. If replacing a Developer ID build already installed in `/Applications`, keep the same certificate and location:

```bash
make deploy APP_BUNDLE=/Applications/TypoFixr.app \
  CERT_NAME="Developer ID Application: <name> (<team>)" \
  CODE_SIGN_FLAGS="--options runtime --timestamp"
```

To prepare an installer while leaving the working app running, deploy to a separate staging folder and disable launch:

```bash
make deploy APP_BUNDLE="$PWD/.build/distribution/TypoFixr.app" \
  CERT_NAME="Developer ID Application: <name> (<team>)" \
  CODE_SIGN_FLAGS="--options runtime --timestamp" LAUNCH_AFTER_DEPLOY=0
```

`LAUNCH_AFTER_DEPLOY=0` skips both stopping and launching the app. Run signing jobs serially; an interrupted codesign process can leave a `.cstemp` file in its build product. Confirm the process has stopped before removing that temporary build file and retrying. If macOS requires Keychain approval, approve it locally. If macOS blocks replacing an app in `/Applications`, use Finder to install the verified DMG.

A change of signing identity can require the user to reauthorize Accessibility even if the old entry is enabled. Never reset the user’s permissions or preferences to hide that mismatch. The app should reopen the missing setup step and display a visible permission icon.

For editing changes, run live selection/replacement/undo and clipboard checks in the reported app. Automated tests and native/WebKit fixtures do not prove compatibility with every third-party editor. Record tested coverage and limits in the notes.

## Distribution workflow

The existing tag-triggered `Release` workflow runs Xcode tests, builds with Developer ID and hardened runtime, notarizes and staples the app, packages `TypoFixr.dmg`, then signs, notarizes, and staples the DMG before creating a GitHub release. It uses the repository’s existing secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `P12_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_ID_PASSWORD`

Do not commit passwords, private keys, certificate exports, or local Keychain profile data. Ordinary push/PR verification runs without release secrets.

A draft can also be prepared locally: copy the verified Release bundle to a separate staging directory, sign it with Developer ID, ZIP it with `ditto -c -k --keepParent`, and submit using `xcrun notarytool submit ... --keychain-profile <profile>`. After Apple returns `Accepted`, staple and validate the app, then package the installer:

```bash
APP_PATH="$PWD/.build/distribution/TypoFixr.app" \
OUTPUT_DMG_PATH="$PWD/.build/distribution/TypoFixr.dmg" \
  bash scripts/package_dmg.sh
```

Sign, submit, and staple the final DMG as well. Use `codesign --verify`, `xcrun stapler validate`, `spctl --assess`, and `hdiutil verify`; mount the DMG read-only to check the app’s version, identity, signature, ticket, and architectures. Generate the checksum after stapling.

Create or update the draft against the full pushed commit SHA, with the notarized DMG, checksum, and notes. Keep its status explicit: a prepared draft has not been published, and does not replace the current latest download. Publishing is a separate release action. Do not push a tag merely to create a draft, because this repository’s existing tag workflow publishes releases.
