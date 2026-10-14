# Contributing to OneWay

Thanks for helping make OneWay more dependable and easier to use. This repository contains both native apps; keep changes focused on the platform or shared behavior they affect.

## Before changing behavior

Open an issue for substantial architectural changes. Small fixes and documentation corrections can go straight to a pull request. Read the [architecture](docs/architecture.md) and [platform limits](README.md#know-the-limits).

Preserve these invariants:

- Additions are unions. An omitted or unchecked item cannot remove a saved block.
- Persist validated state before enforcing it or showing success.
- Failed writes and corrupt files never silently replace a list with an empty list.
- Do not add reset, pause, timer, or remove controls to the normal interface.
- Do not alter unrelated hosts entries, kill unrelated processes, or trust arbitrary clients of the privileged service.
- Status text must distinguish saved configuration from verified enforcement.

## Development setup

Clone the complete repository and follow the platform guides. Keep team IDs and signing identities in the ignored local configuration files. Do not change bundle identifiers on an existing installation unless you deliberately want a separate app/data identity.

Run the local checks:

```sh
./scripts/test.sh
./OneWayMac/build.sh --unsigned
xcodebuild -project OneWay/OneWay.xcodeproj -scheme OneWay \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath OneWay/.build/Simulator CODE_SIGNING_ALLOWED=NO build
```

Use temporary files and disposable apps for automated tests. Do not add test domains or apps to your real permanent list. A separate development bundle identifier is appropriate for physical-device experiments. CI never needs certificates, Apple account credentials, root access, or a registered phone.

## Pull requests

Describe the problem, the resulting behavior, and how you verified it. Include a screenshot for interface changes. Add regression coverage when changing persistence, domain parsing, IPC authorization, or enforcement. Clearly separate compilation/model tests from on-device/browser checks you actually performed.

Use Swift's standard formatting and descriptive names. Keep permission-sensitive operations out of previews and tests. Avoid unrelated dependency or formatting churn. By submitting a contribution, you agree that it is provided under this project's MIT license.

## Reporting issues

Include your OS, Xcode version, affected platform, exact reproduction steps, expected behavior, and observed behavior. For Mac website issues, say whether a full browser quit/reopen changes the result. Redact personal URLs and identifiers when possible. Use private security reporting for vulnerabilities rather than public issues.
