# JustThirty for Mac

## Daily access

All saved apps and websites share **30 minutes of timed access per day on each device**. Start the timer to unlock; pause to block again and keep your remaining time for later. For example, 13 minutes used leaves 17 minutes. Time keeps running while you are away unless you pause. The lists remain add-only.

See [daily access behavior, setup, and limitations](../docs/daily-access.md). On Mac, only apps explicitly saved in the block list close when access ends; save work in those apps first. Website rules resume without closing unrelated browsers, tabs, windows, or profiles. Existing connections may persist until you quit and reopen the browser yourself.

The browser-preservation fix is in the unreleased build 8 source. The published Mac RC1 package contains build 7 and still has the earlier automatic browser-closing behavior. Building this source does not update an installed background service.


[Project overview](../README.md) · [Troubleshooting](../docs/troubleshooting.md)

A native macOS companion to the iPhone app. Universal Apple silicon and Intel build, installed directly. The Mac and iPhone keep separate lists and daily budgets. This architecture uses an administrator-approved service and is not eligible for the sandboxed Mac App Store.

## Use

Open `/Applications/JustThirty.app` (upgrades may retain `/Applications/OneWay.app`). Choose **Set up**, then approve JustThirty in **System Settings → General → Login Items & Extensions → App Background Activity** (Apple may display the developer's name). An administrator must approve the launch daemon. Return to JustThirty and wait for **Ready for your first block**.

Use **Add websites** to search the local catalog or paste a hostname/URL. The preview lists every exact hostname that will be added, including `www` and known aliases. Confirm before saving. Use **Add apps** to choose from installed apps or browse to a `.app`; save your work first, as the app will be terminated. Additions cannot be removed or reset through the interface or its service protocol. Timed access is limited by the persisted daily allowance.

**After adding a website, fully quit and reopen your browsers.** A tab refresh or closing one window may retain cached connections. This was observed in Chrome during local testing and resolved after a full browser restart. Confirm blocking in each browser you use.

Closing or quitting the interface does not stop the daemon. After approval, macOS launches the daemon at boot. The app reports a disconnected or unhealthy state instead of claiming protection when the daemon cannot be reached.

## What this version enforces

- **Websites:** root-owned `/private/etc/hosts` rules for the exact hostnames shown in the confirmation, on IPv4 and IPv6. Existing entries and comments outside OneWay's marked section are preserved. The first changed hosts file is backed up. Rules are checked every three seconds, and macOS DNS caches are flushed when they change.
- **Apps:** a background process watcher checks every half second. It identifies selected apps by bundle ID and original bundle path, including their nested helpers, and sends `SIGTERM`, followed by `SIGKILL` if they are still running after a second. Only user processes (UID 501 or greater) are targeted. Process identity is rechecked before signaling to reduce PID reuse risk.
- **Storage:** an append-only logical list saved by a root service under `/Library/Application Support/OneWayMac/block-list.json`. The directory is mode 700; the file is mode 600. Updates are validated and atomically committed before enforcement. Invalid stored data blocks further additions instead of silently resetting the list.
- **IPC:** the app and helper authenticate one another by Apple code-signing anchor, team ID, and exact bundle identifier. Only snapshot, add-domain, add-app, and bounded start/pause operations exist. Neither side accepts shell commands or reset requests over XPC.

This is a commitment aid, not tamper-proof device management. It does not intercept application launches at the kernel level: an app can appear briefly before being closed. A website's unlisted subdomains, external proxies, some encrypted DNS/browser configurations, direct IP access, and cached browser connections can bypass hosts-based rules. There is no wildcard filtering. Existing tabs may need closing/reopening. System recovery apps and the tools used to maintain OneWay are intentionally excluded from app selection. An administrator can disable the service or edit its data/rules. The rules apply across this Mac, not just one browser. Installing the iPhone app on a Mac is not used as the enforcement mechanism.

No browsing history or website searches are sent anywhere. Catalog search is local. Existing manually configured hosts rules are preserved but are not silently imported into OneWay's permanent list.

## Build and validate

Requires Xcode command line tools, Python 3, macOS 14+, and a Developer ID Application signing identity in your keychain. Clone the whole repository so the shared iPhone sources and icon are available. Both architectures compile; physical Intel validation remains a release check.

Copy `.signing.example.json` to `.signing.json` and set your team ID, signing identity, and unique bundle identifier. This file is ignored by Git. You can alternatively provide `ONEWAY_TEAM_ID`, `ONEWAY_SIGNING_IDENTITY`, and `ONEWAY_BUNDLE_ID` environment variables. The build generates matching identities and plists for both executables; do not weaken the signing checks to use a preview build as a privileged service.

```sh
./test.sh
./build.sh
./install.sh
```

`build.sh` produces universal `.build/JustThirty.app` and verifies both code signatures. It uses the website catalog and domain parser from `../OneWay/OneWay/BlockList.swift` and the iPhone app's icon. `prepare-build.py` generates the app ID, helper ID, team requirement, and plist identities from your local configuration. The helper ID is your app ID plus `.helper`. Keep these identifiers stable for in-place updates.

For a credential-free compile/UI preview, use `./build.sh --unsigned`. It writes `.build/unsigned/JustThirty.app`, uses an isolated preview identifier, ignores local signing settings, and applies an ad-hoc signature. It cannot authenticate to the production service and should not be installed as a blocker.

Signed builds use Developer ID and the hardened runtime. Use `../scripts/package-mac.sh YourNotaryKeychainProfile` for notarization, stapling, Gatekeeper assessment, and a distributable disk image. Without a profile the script produces an explicitly unnotarized preparation package. Do not offer that as a public download.

An alternative using the signed-in Xcode account is `../scripts/archive-mac.sh`. Open the archive, choose **Distribute App → Direct Distribution**, wait for Apple's acceptance, then export the notarized app. Run `../scripts/package-notarized-mac.sh /absolute/path/to/JustThirty.app` to validate both architectures, the signature, staple, and Gatekeeper before creating a ZIP and portable SHA-256 checksum. Do not rebuild or re-sign the exported app after notarization.

The test suite uses temporary state and hosts files and a disposable app process. It covers monotonic additions, disk persistence, corrupt data, save failures, domain validation, aliases and lookalikes, existing hosts preservation, marker corruption, permissions, backups, symlink rejection, nested app helpers, termination/relaunch, and leaving unrelated processes alone. It never adds real sites or apps to the user's permanent list or changes the real hosts file.

## Maintenance

The bundled helper lives at `JustThirty.app/Contents/Library/HelperTools/OneWayHelper`, registered using `SMAppService` and the generated launch-daemon plist. Existing installations may retain the original OneWay bundle path. Do not uninstall the app or delete the service data during updates. Updating a running helper may require a deliberate service restart/re-registration during development; verify the running service after installing a new helper binary. Keep existing data and hosts rules throughout that maintenance.

There is deliberately no end-user reset/uninstall script. If the user explicitly requests a code-assisted change later, inspect the authoritative root-owned list and marked hosts section and make only the requested change. Never overwrite the entire hosts file from the backup, because unrelated tools may have edited it in the meantime.

Apple references: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [XPC signing requirements](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)).
