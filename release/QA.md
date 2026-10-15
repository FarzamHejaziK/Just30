# JustThirty 1.3 validation

Checked October 15, 2026. iPhone build 8; Mac build 7. This report records observed results and open checks, not a claim that every supported device has been tested.

| Area | Result | Evidence and limits |
| --- | --- | --- |
| Shared data and accounting | Pass | Add-only persistence, invalid/corrupt state, 13 + 17 minute accounting, repeated pause/resume, exhaustion, clock rollback, calendar midnight, DST. |
| Monitor registration regression | Pass | A synchronous simulated callback acquires the storage lock during registration. Failed, stale, and expired registrations leave stored access locked and cancel the monitor. |
| iPhone device build | Pass | Release 1.3 (8), signed and installed in place on iPhone 17 Pro Max; existing list and 29:08 paused balance retained. |
| Resume hang | Fixed; device check passed | Build 7 watchdog reports pointed to `startMonitoring` inside the shared persistence lock. Build 8 registers outside that lock and performs system calls on a serial worker. Two successive Resume/Pause cycles completed; unused time remained. No build 8 crash report appeared during the check. |
| Selected-app restriction | Pass on test phone | A previously saved app displayed Apple's Restricted screen after Pause. No new production block was added for this check. |
| Typed website filtering | Open | A saved domain showed a blank loading page during the device check. That is not authoritative proof of filtering; verify both blocked and unlocked states before App Review. |
| Background deadline | Open | Complete a full expiry while the app is backgrounded/phone locked, then test a short remaining session. Do not reset production budgets or alter the clock to simulate this. |
| iPhone layouts | Pass on local simulator | iOS 26.5: SE 3rd generation, iPhone 17, and 17 Pro Max. Large accessibility text, scrolling confirmation, local search, previews, long domains, and reachable actions checked. Simulator fixtures do not verify Screen Time. |
| Older iOS versions | Open | Minimum target is iOS 17.4; only iOS 26.5 simulator runtime is available locally. |
| Mac build and service | Pass on Apple silicon | Universal arm64/x86_64, minimum macOS 14, hardened runtime. Updated background helper matched build 7 and reported healthy; saved list and exhausted daily budget retained. |
| Mac enforcement | Pass with stated limits | 41 checks use temporary hosts/state and a disposable app. Termination, relaunch, process identity, unrelated processes, preservation of hosts entries, permissions, and disk failures covered. Fresh system resolution of an existing saved hostname returned blocking addresses. Cached browser connections remain a documented limitation. |
| Mac performance | Improved in measured workload | Caching executable-to-app identity reduced 50 warm watcher sweeps from 28.933 ms to 3.336 ms on the local M4. This is a microbenchmark, not a battery-life or cross-hardware guarantee. |
| Mac public package | Verified and published as RC1 | Apple's Xcode Direct Distribution notarization accepted; strict deep signature, stapled ticket, Gatekeeper (`Notarized Developer ID`), and both architectures pass. ZIP and SHA-256 produced without re-signing the accepted export; published as `mac-v1.3-rc.1`. |
| Physical Intel / older macOS | Open | Both architectures compile; physical Intel and macOS 14 runtime have not been tested. |
| Website | Pass | Live root, privacy, and support URLs return HTTP 200. Desktop and 375/320 px layouts checked, no horizontal overflow at 320 px, demo Start/Pause/Resume works, no browser console errors in the checked session. |
| Original logo | Preserved | Native icon and website asset match the original SHA-256: `cacd358e71aa1d11e8cc5b8f00880b9e63422023c996eb3db0d5ea33f91b0085`. |

## Store status

The App Store record is a draft, not a public release. Five screenshots uploaded successfully and are reused for the required smaller display class. Subtitle, categories, 4+ global age rating (regional exceptions), content rights, support/marketing/privacy URLs, and private App Review contact are saved. The Data Not Collected privacy label is published after the owner confirmed Apple's accuracy attestation. Free ($0.00 base price) pricing and availability in 175 countries or regions are saved for release. iPhone-on-Mac and Vision Pro distribution are disabled; the native Mac uses direct distribution. The owner declared the app a personal hobby with no commercial activity. The EU non-trader declaration is saved and Apple shows Digital Services Act compliance as Active; no public trader contact details were supplied.

Family Controls distribution approval is pending for the app and monitor. The earlier export failed because their distribution profiles did not include the entitlement. A development-signed archive is not an App Store-exportable build. Complete device checks and distribution signing before uploading or submitting.

Private logs, screenshots of real selections, device identifiers, signing materials, and App Review contact details remain outside source control.
