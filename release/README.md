# JustThirty release preparation

Target: version 1.3; iPhone build 8 and Mac build 7. Free iPhone app; signed, notarized direct Mac distribution. The current administrator-service Mac design is not eligible for the sandboxed Mac App Store. Preserve the original icon and existing bundle/service/data identities during upgrades.

## Current gates

- Family Controls distribution request submitted; Apple approval pending. App Store export currently fails because the app and monitor profiles lack `com.apple.developer.family-controls` for distribution. Development signing or archive success does not satisfy this gate.
- App Store Connect version 1.3 draft is saved with copy, review notes, five screenshots, subtitle, categories, age rating, content rights, live URLs, and private App Review contact. The Data Not Collected privacy label is published after the owner's confirmation. Free pricing and worldwide availability are saved for release; the owner's EU non-trader declaration is saved and DSA compliance is Active.
- Physical iPhone build 8 preserves the existing list/balance, completes repeated Resume/Pause, and restricts a saved app while paused. Website blocked/unlocked states and background expiry remain required checks. Build 7 had a confirmed Resume watchdog hang; the registration/locking regression is fixed and covered by tests. Simulator fixtures verify layout only.
- Mac universal build 7 is signed and notarized through Xcode Direct Distribution. The exported ZIP passes strict signature, stapled-ticket, and Gatekeeper checks. The older unnotarized DMG is obsolete and must not be offered as a download.
- The Mac package and portable SHA-256 checksum are public in [Mac 1.3 RC1](https://github.com/FarzamHejaziK/Just30/releases/tag/mac-v1.3-rc.1). This is a prerelease, with runtime coverage limitations stated in the release notes.
- Intel is compiled but has not been tested on physical Intel hardware. Older iOS versions require additional runtime/device testing; the local simulator runtime is iOS 26.5.
- Website is live at https://justthirty.vercel.app with verified privacy/support pages. The App Store uses these stable URLs. See [QA.md](QA.md) for measured results and outstanding runtime checks.

## Repeatable checks

```sh
./scripts/test.sh
node --check website/app.js
./scripts/archive-ios.sh
./scripts/package-mac.sh YourNotaryKeychainProfile
```

Use a dedicated test device or simulator when adding entries, because production lists are intentionally add-only. Never erase a user's data to get a clean screenshot. DEBUG Simulator `--screenshot-mode` supplies an isolated example.com fixture and bypasses real enforcement only for layout review; it is absent from device/release builds.

## App Store copy

`app-store/en-US/metadata.json` contains constrained-length text and review notes. No login is required. No purchases or subscriptions exist. Data is stored and used locally; the intended privacy label is Data Not Collected, subject to final verification against the submitted binary.

Screenshots must be captured at Apple's accepted sizes from the current interface. Use the website's stable privacy and support pages after deployment. Do not display an App Store badge or download link before a public release actually exists.

## Signing and notarization

Keep local signing configs, certificates, profiles, keys, device identifiers, logs, and runtime lists ignored. Do not put credentials in scripts or command arguments. Store notarization credentials interactively in Keychain with Apple's `notarytool store-credentials`, then provide only the profile name to the packaging script.

Alternatively, use `./scripts/archive-mac.sh` and Xcode **Distribute App → Direct Distribution** with the signed-in Apple account. After acceptance, export the notarized app and run `./scripts/package-notarized-mac.sh /absolute/path/to/JustThirty.app`. This validates and packages the accepted bundle without re-signing.

The packaging script produces a final release name only after successful checks. An artifact ending in `-unnotarized.dmg` must not be presented as a public release.
