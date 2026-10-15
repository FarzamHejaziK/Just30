# JustThirty for iPhone

## Daily access

All saved apps and websites share **30 minutes of timed access per day on each device**. Start the timer to unlock; pause to block again and keep your remaining time for later. For example, 13 minutes used leaves 17 minutes. Time keeps running while you are away unless you pause. The lists remain add-only.

See [daily access behavior, setup, and limitations](../docs/daily-access.md). On Mac, supported browsers and blocked apps close when access ends; save your work first.


[Project overview](../README.md) · [Troubleshooting](../docs/troubleshooting.md)

A native iPhone blocker with an add-only list. Built with SwiftUI, FamilyControls, and ManagedSettings. No server or analytics. Direct development installation is available; the first App Store release is in preparation.

## Behavior

- Grant individual Screen Time access, then add apps, entire categories, picker websites, or typed website domains.
- Review each addition before committing. Existing selections are unioned with new selections; deselecting something in the picker never removes a saved block.
- Website entry offers local autocomplete for familiar sites, URL-to-domain previews, visible alias domains, and already-blocked indicators. Custom domains also work. Suggestions never query a remote service or visit the website. Confirmed additions keep the screen open for the next website.
- There are no removal or reset controls. Daily Access unlocks the saved list for a countdown within the 30-minute daily budget.
- Blocks use a named ManagedSettings store. The app and monitor extension apply or lift its restrictions according to the saved session deadline.
- Additions are saved atomically before being applied. Unreadable saved data disables edits rather than overwriting the list. A failed save leaves the previous list intact.
- Apple tokens stay opaque; labels are rendered by Apple's UI. The saved list and daily allowance stay in the shared App Group container. Legacy Application Support data is migrated by union and retained.

## Platform limits

This does not make the phone impossible to bypass. Individual Screen Time authorization can be revoked in Settings; app deletion, data loss, signing expiry, and OS changes remain outside this app's guarantees. Website enforcement must be verified in each browser and in-app browser used. Typed-domain filtering also disables Safari Private Browsing.

This version supports 50 individual app tokens, 50 category tokens, 50 picker website tokens, and 50 typed domains. A transaction exceeding a limit is rejected in full. Category selection restricts apps and websites in that category, including future category members. The app makes no promise of continuous enforcement after authorization is revoked.

There is intentionally no recovery UI. Changing the policy requires a deliberate source-code change and rebuilding. Reinstall updates over the existing app to preserve its saved data; do not delete the app first.

## Build and install

Copy `Signing.example.xcconfig` to `Signing.local.xcconfig`, then enter your Apple Developer team ID and a unique bundle identifier. The local file is ignored by Git. Open `OneWay.xcodeproj` in Xcode; it uses automatic signing and the Family Controls development entitlement. Deployment target: iOS 17.4 or later, iPhone only. Keep your bundle identifier unchanged when updating an existing installation.

1. Pair and trust the iPhone.
2. Enable Settings → Privacy & Security → Developer Mode on the phone, restart, and confirm.
3. Install the iOS platform support offered in Xcode Settings → Components.
4. Select the iPhone and Run. Resolve Apple account or agreement prompts with the account holder.
5. Open JustThirty and grant Screen Time access yourself.

Use a paid Apple Developer membership for this documented setup and confirm your team's Family Controls provisioning eligibility. Development signing may create an App ID, register the device, and generate a provisioning profile. This is not an App Store submission. Family Controls distribution approval is separate from direct development provisioning; distribution requires its own entitlement review.

After initial setup, `./install.sh <iPhone UDID>` builds, installs in place, and launches the app. It never uninstalls the old version or resets its data.

Never commit a device UDID, provisioning profile, certificate, or signing key. Run the install command locally with your own paired device. For Simulator-only compilation, no developer signing is needed:

```sh
xcodebuild -project OneWay.xcodeproj -scheme OneWay -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/Simulator \
  CODE_SIGNING_ALLOWED=NO build
```

## Local regression checks

From this directory:

```sh
mkdir -p .build
swiftc OneWay/BlockList.swift Tests/BlockListTests.swift -o .build/block-list-tests
.build/block-list-tests
```

The same generic model and persistence code used on the phone are tested with string tokens: additions across reloads, omission of earlier choices, duplicate and empty submissions, domain parsing, capacity checks, corrupt files, and failed saves.

## On-device acceptance checks

Actual Screen Time enforcement requires a physical iPhone. Only add a test app/site you really intend to keep blocked, or use a separate disposable development bundle ID for testing.

- Grant access and verify the native picker opens.
- Add one app, close JustThirty, and verify iOS shields that app.
- Add another app and verify the first remains blocked.
- Add a domain and check Safari plus any other browsers you use; check relevant subdomains separately.
- Force-quit/relaunch JustThirty and restart the phone; verify persistence and blocking.
- Start access, pause, and resume; verify the balance is preserved and the same apps/websites re-block on pause and exhaustion.
- Verify expiry while the app is backgrounded and while the phone is locked, including a resumed session shorter than 15 minutes.
- Confirm no row swipe, picker edit, or app control removes previous entries.

Compilation and the model tests alone do not prove on-device blocking.

## Apple references

- [Family Controls setup](https://developer.apple.com/documentation/Xcode/configuring-family-controls)
- [Individual authorization and named stores](https://developer.apple.com/videos/play/wwdc2022/110336/)
- [Website filter behavior](https://developer.apple.com/documentation/managedsettings/webcontentsettings/blockedbyfilter-swift.property)
