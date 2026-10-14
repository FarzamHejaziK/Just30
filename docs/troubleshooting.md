# Troubleshooting

## A Mac website still loads after adding it

1. Check that the exact hostname shown in the browser address bar appears in OneWay. `example.com`, `www.example.com`, and `app.example.com` are distinct hostnames. Confirm any required additions in the app.
2. Save unfinished browser work, then **fully quit the browser with ⌘Q and reopen it**. Closing a tab, closing a window, or refreshing can leave cached connections alive. This resolved the issue during local testing.
3. Check that OneWay can reach its background service and does not show an enforcement error.
4. Consider proxies, custom DNS/browser configurations, cached offline pages, and direct IP access. Hosts rules are not a comprehensive browser/network filter.

For developer diagnosis, check the system resolver without changing settings:

```sh
dscacheutil -q host -a name example.com
curl --noproxy '*' -I --connect-timeout 5 https://example.com
```

Replace the example with a domain you already chose to block. A configured domain should resolve to `0.0.0.0` / `::1`. A failed fresh connection confirms the system rule, not the behavior of an existing browser session. Do not disable security features to make OneWay work.

## The Mac helper cannot connect

Keep the signed app in `/Applications/OneWay.app`. Open it, choose **Set up**, and inspect **System Settings → General → Login Items & Extensions**. An administrator may need to approve its background activity. The label may show OneWay or the signing developer's name.

An unsigned preview cannot activate the authenticated production service. For a signed build, the app, helper, generated identifiers, and team requirement must agree. Use `build.sh` rather than signing one binary manually. Check the code signature with:

```sh
codesign --verify --deep --strict /Applications/OneWay.app
```

After replacing a running helper during development, its previous process may still be running. Follow deliberate administrator maintenance to restart/re-register that service while preserving the root-owned list and hosts section. Never delete the state directory as a generic troubleshooting step.

## A Mac app appears briefly or loses unsaved work

The watcher closes an app after it starts; it does not intercept the launch. Save work before confirming a block. The service tries termination, then force-terminates a matching process that remains. System recovery apps are excluded. Sandboxed or privacy-protected app locations can also cause access errors; inspect the reported error rather than broadening permissions blindly.

## iPhone signing or authorization fails

Confirm your local team/bundle configuration, Family Controls capability, provisioning eligibility, Xcode's platform support, device trust, and Developer Mode. Apple account agreement or permission prompts must be resolved by the account holder. Use a physical iPhone for enforcement checks; Simulator compilation is not a substitute.

If Screen Time access was revoked, authorize again in OneWay. If iOS rejects authorization, inspect the phone's Screen Time settings and the underlying error. Do not delete the app to fix signing without considering that this can delete its saved list.

## A saved list cannot be read

Stop adding entries. Preserve the original file and diagnostic error. OneWay intentionally refuses to reset corrupt data silently. Repair should be a deliberate developer-assisted operation with a backup and only the requested change. Do not restore the entire old hosts file over the current one: other software may have added unrelated rules since the backup.

## I changed phones, bundle IDs, or signing configuration

There is no cross-device synchronization or migration UI. Changing an app's bundle identifier can create a separate data identity. Keep identifiers stable for in-place updates and review saved data before a migration.

## I found another issue

Use the [bug report template](https://github.com/FarzamHejaziK/OneWay/issues/new?template=bug_report.yml), including OS/browser/Xcode versions and reproduction steps. Use [private reporting](../SECURITY.md) for security vulnerabilities. Redact private data.
