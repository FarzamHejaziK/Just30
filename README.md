<p align="center"><img src="OneWay/OneWay/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="JustThirty logo"></p>
<h1 align="center">JustThirty</h1>
<p align="center"><strong>A little access. A clear stopping point.</strong><br>Native focus apps for iPhone and Mac. Free and open source.</p>
<p align="center"><a href="https://github.com/FarzamHejaziK/OneWay/actions/workflows/ci.yml"><img src="https://github.com/FarzamHejaziK/OneWay/actions/workflows/ci.yml/badge.svg" alt="Build and test"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a></p>

Choose distracting apps and websites, then give all of them **one combined 30-minute daily allowance per device**. Start to unlock. Pause to block again and save the unused time. Resume later. Thirteen minutes used leaves seventeen minutes for the rest of the day.

Your list is add-only: new entries are merged with saved entries, and there is no in-app remove or reset button. Review additions carefully. The timer continues while you switch away, lock the device, or close the app; pause explicitly to preserve time.

JustThirty was originally named OneWay. The repository, internal bundle IDs, service names, and data locations retain that name to preserve existing installations. The original logo is unchanged.

## Release status

Version 1.3 is being prepared for public distribution. **The iPhone app is not published on the App Store.** Apple has accepted the signed universal Mac package for notarization; Gatekeeper and its stapled ticket pass verification. See the [release checklist](release/README.md), [validation report](release/QA.md), and [App Store materials](release/app-store/en-US/metadata.json). A successful build is not proof of Screen Time enforcement.

Visit [justthirty.vercel.app](https://justthirty.vercel.app) for the product overview, interactive preview, [support](https://justthirty.vercel.app/support/), and [privacy policy](https://justthirty.vercel.app/privacy/).

| | iPhone | Mac |
| --- | --- | --- |
| Minimum OS | iOS 17.4 | macOS 14 |
| Hardware | Supported iPhones running the minimum OS | Universal Apple silicon and Intel build |
| Blocking | Apple Family Controls and Managed Settings | Local administrator-approved background service |
| Websites | Screen Time filtering, depending on browser support | Explicit IPv4/IPv6 host rules |
| Apps | Selected apps and categories | Selected user apps close after launch |
| Daily allowance | 30 minutes shared across saved apps and websites | Independent 30 minutes shared across saved apps and websites |
| Data | Local app group shared with the monitor extension | Protected local service state |
| Public distribution | App Store, after entitlement approval and app review | Signed and notarized website download |

## Privacy and limits

The apps have no account, analytics, advertising, cloud sync, or third-party runtime dependencies. Selections and timer state stay on the device. Suggestions are searched locally. The website is a separate static marketing site; its hosting provider processes ordinary web requests. See [privacy](docs/privacy.md).

JustThirty is a personal commitment tool. iOS lets the owner revoke Screen Time authorization or delete the app. A Mac administrator retains system control. Website coverage varies by platform and browser; proxies, alternative DNS behavior, additional hostnames, cached content, and existing connections can bypass Mac host rules. Typed website restrictions on iPhone also disable Safari Private Browsing.

**Save browser work before pausing or ending access on Mac.** Supported browsers close to clear connections, which can interrupt unsaved work. Adding a blocked app also closes it. The watcher checks about twice a second, so an app may appear briefly. There is no kernel-level launch prevention or Network Extension firewall.

The lists and budgets do not sync. Allowances reset at midnight in the original allowance time zone. Unused time does not carry over. Reinstallation, backup restoration, signing expiry, authorization changes, or loss of local data can affect enforcement.

## Build and install

Clone the entire repository; both apps share the domain parser, allowance logic, and original icon.

```sh
git clone https://github.com/FarzamHejaziK/OneWay.git
cd OneWay
./scripts/test.sh
```

For iPhone, install Xcode with iOS support. Copy `OneWay/Signing.example.xcconfig` to the ignored `OneWay/Signing.local.xcconfig`, set your team and unique bundle ID, then run the OneWay scheme on a paired iPhone. Enable Developer Mode and authorize Screen Time. A paid developer account capable of provisioning Family Controls is needed for this setup. Public distribution requires Apple's separate Family Controls approval for the app and its monitor. See the [iPhone guide](OneWay/README.md).

For Mac, use Xcode tools and a Developer ID Application certificate. Copy `OneWayMac/.signing.example.json` to ignored `OneWayMac/.signing.json`, configure your identity, then run:

```sh
./OneWayMac/install.sh
```

Approve the background service when requested. New installs use `/Applications/JustThirty.app`; upgrades retain `/Applications/OneWay.app` when present so existing service registration keeps its path. Do not move the installed bundle. See the [Mac guide](OneWayMac/README.md).

### Preview without production signing

```sh
./OneWayMac/build.sh --unsigned
xcodebuild -project OneWay/OneWay.xcodeproj -scheme OneWay \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath OneWay/.build/Simulator CODE_SIGNING_ALLOWED=NO build
```

The ad-hoc Mac preview is `OneWayMac/.build/unsigned/JustThirty.app` and cannot activate the authenticated production helper. iPhone Simulator screenshots can use the DEBUG-only `--screenshot-mode` fixture; this mode performs no Screen Time authorization or enforcement and is excluded from release/device builds. A physical iPhone is required to validate actual shielding and background expiry.

## Packaging and website

```sh
./scripts/archive-ios.sh
./scripts/package-mac.sh YourNotaryKeychainProfile
python3 -m http.server 4173 --directory website
```

The iOS script archives and exports without uploading. It fails if distribution entitlements are unavailable. The Mac script builds both architectures, signs, notarizes, staples, and assesses the artifacts. Without a notary profile it creates a clearly marked unnotarized package for preparation only. Do not distribute that package as a finished release.

Alternatively, run `./scripts/archive-mac.sh`, open the resulting archive in Xcode, and choose **Distribute App → Direct Distribution**. After Apple accepts it, export the notarized app and run `./scripts/package-notarized-mac.sh /absolute/path/to/JustThirty.app`. This route uses the signed-in Xcode account and packages the accepted bundle without re-signing it.

The `website/` directory is a buildless, responsive Vercel site with an interactive timer preview, privacy policy, and support page. The demo controls no restrictions. Deploy only that directory, keeping signing files and device data out of uploads.

## Project map

| Path | Purpose |
| --- | --- |
| `OneWay/` | iPhone SwiftUI app, Screen Time monitor, Xcode project, domain tests |
| `OneWayMac/` | Mac UI, authenticated XPC helper, host/process enforcement, tests |
| `Shared/` | Daily allowance, pause/resume session accounting, regression tests |
| `website/` | Marketing site, privacy policy, support, Vercel configuration |
| `release/` | Store metadata, packaging information, release checklist |
| `scripts/` | Regression checks, archive/export, universal Mac packaging |
| `docs/` | Architecture, behavior, privacy, troubleshooting |

See [architecture](docs/architecture.md), [daily access](docs/daily-access.md), and [troubleshooting](docs/troubleshooting.md). Bug fixes and accessibility improvements are welcome; follow [CONTRIBUTING.md](CONTRIBUTING.md). For help, [open an issue](https://github.com/FarzamHejaziK/OneWay/issues/new/choose). Public posts must not include credentials, device identifiers, or private block lists. Report vulnerabilities through [SECURITY.md](SECURITY.md).

Made by [Farzam Hejazi](https://github.com/FarzamHejaziK). [MIT License](LICENSE).
