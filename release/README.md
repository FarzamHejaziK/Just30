# JustThirty release preparation

Target: version 1.3, build 7. Free iPhone app; signed, notarized direct Mac distribution. The current administrator-service Mac design is not eligible for the sandboxed Mac App Store. Preserve the original icon and existing bundle/service/data identities during upgrades.

## Current gates

- Family Controls distribution request submitted; Apple approval pending. App Store export currently fails because the app and monitor profiles lack `com.apple.developer.family-controls` for distribution. Development signing or archive success does not satisfy this gate.
- App Store Connect draft created. Copy and review notes prepared. Store screenshots, app information, privacy answers, pricing, contact details, and availability must be verified in the dashboard before submission.
- Physical iPhone verification must prove authorization, saved-app and website shielding, pause/resume, expiry while locked/backgrounded, and persistence. Simulator fixtures verify layout only.
- Mac universal signed build succeeds. Notarization credentials are not configured; the unnotarized DMG is preparation only. Verify both notarization and Gatekeeper before offering downloads.
- Intel is compiled but has not been tested on physical Intel hardware. Older iOS versions require additional runtime/device testing; the local simulator runtime is iOS 26.5.
- Website deployment and public URLs must be verified before entering marketing, support, and privacy URLs in App Store Connect.

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

The packaging script produces a final release name only after successful checks. An artifact ending in `-unnotarized.dmg` must not be presented as a public release.
