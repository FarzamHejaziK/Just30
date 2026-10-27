# Daily access

OneWay offers **30 minutes per device, per day**, shared by every app and website on that device's block list. The iPhone and Mac budgets are independent. No browser extension or server is used.

Tap **Start access** to unlock all saved apps and websites and start the shared countdown. Tap **Pause access** to block them again and save the remaining time. Tap **Resume access** to continue where you left off. For example, using 13 minutes and pausing leaves 17 minutes for later that day. At zero, everything re-blocks and access stays unavailable until the next day. Entries remain add-only.

This is a manual start/pause timer, not automatic foreground-usage measurement. While running, it counts down even when you switch apps, lock the screen, sleep the device, or close OneWay. Pause before stepping away if you want to save time. Pausing clears the session and returns only its unelapsed time to the daily budget, in the same atomic transaction. Duplicate pause requests cannot add time. The remaining balance survives relaunches.

Sessions end no later than midnight, with a fresh budget on the next calendar day and no carryover. The time zone recorded when the allowance is first created determines midnight, including daylight saving time. Changing the device time zone does not grant extra time. An administrator or device owner changing the system clock, deleting data, revoking authorization, or disabling the service can still bypass OneWay; it is not a tamper-proof control.

## iPhone

An embedded Device Activity Monitor extension restores the app and website restrictions after the scheduled session. The extension and app share an App Group container and serialize state changes with a file lock. Existing lists migrate by union into the shared container; the old file is retained. The app arms the background monitor before saving an unlock. If monitoring cannot be registered, it does not unlock anything. Reopening the app reapplies restrictions if a session expired or its monitor is missing.

The countdown uses a nonrepeating Device Activity schedule. Its start is in the recent past to meet Apple's minimum interval length for short resumed sessions. Enforcement depends on iOS delivering monitor callbacks and on supported website filtering; it is not a guarantee of an exact-to-the-second hard cutoff. Verify background re-blocking on a real iPhone before relying on it. Simulator builds cannot validate Screen Time enforcement. You may need to reopen Safari after website filtering changes.

Building now requires iOS 17.4+, Family Controls for the app and monitor target, and an App Group shared by both. `ONEWAY_APP_ID` and `ONEWAY_APP_GROUP` in the Xcode configuration derive consistent bundle and group identities. Automatic signing provisions development profiles; distribution entitlements are a separate Apple process.

## Mac

The privileged helper owns the persisted budget and session deadline. It checks expiry every half-second, so the interface can be closed without stopping enforcement. Existing non-OneWay hosts entries remain untouched, including entries that may independently keep a site blocked during a session. Corrupt daily-access state disables access while retaining normal blocking.

**Save work in explicitly blocked apps before starting.** At session end, OneWay restores its hosts section, flushes DNS, and closes only the applications saved in the block list. Pausing does the same, while preserving remaining time. A website rule does not select a browser for termination. If you explicitly blocked the browser app itself, it is treated like any other selected app and closes, affecting its windows and profiles. Selected processes that do not exit receive SIGKILL after one second, which can lose unsaved work.

Hosts rules cannot cut off existing browser connections or remove already loaded content. An open site may remain accessible after expiry until its connection is renewed or you manually quit and reopen the browser. Proxies, secure DNS, embedded web views, and unlisted subdomains may bypass hosts-based blocking. Browsers may need restarting when access starts too, because failed DNS responses can be cached. The rules remain machine-wide; they are not a per-tab network filter or a guaranteed immediate website cutoff.

Unreleased Mac build 8 removes the old three-second sweep that automatically closed all supported browsers. Older persisted `pendingBrowserClose` markers are cleared without resetting the saved list, active deadline, or current-format budget. The field remains in the shared data format for older-reader compatibility. The published RC1 package is build 7 and does not yet contain this fix.

The earlier fixed-duration prototype discarded unused minutes when access ended early. Its paused counters receive a one-time fresh budget during migration to pause/resume accounting; current-format counters never receive this migration reset.

## Validation

`./scripts/test.sh` covers shared-budget aggregation, persistence, overlap rejection, pause/resume accounting, exhaustion, clock rollback, calendar rollover, DST, and midnight truncation. Mac service regressions exercise active access, expiry, Pause/Resume, additions during access, and legacy state on restart. Tests use temporary hosts/state, a fake clock, and disposable apps; the application probe refuses non-fixture targets before any signaling. They never edit the real block list, flush system DNS, or consume the user's daily allowance. Build checks cover the iOS app and extension plus the signed Mac app/helper.
