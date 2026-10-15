# Changelog

## 1.3 - Release preparation

- Rename the app to JustThirty while preserving bundle identities, saved data, and the original logo.
- Add shared 30-minute daily access with precise Start/Pause/Resume accounting on each device.
- Improve Dynamic Type layouts and reduce unnecessary state writes and refreshes.
- Compile a universal Mac app, scan installed apps off the main thread, and cache unchanged host enforcement.
- Add an iPhone privacy manifest, store metadata, archive/export and notarization scripts, and a Vercel landing page with support and privacy pages.
- Public distribution remains pending entitlement approval, physical-device verification, and notarization.

## 1.2.0 — 2026-10-14

- Added Start / Pause / Resume controls with persistent 30-minute daily access budgets on iPhone and Mac, shared by all saved apps and websites on each device.
- Added an iPhone Device Activity monitor extension and App Group migration.
- Added helper-owned Mac countdown enforcement and browser connection cleanup at expiry.
- Added budget persistence, rollover, exhaustion, overlap, and midnight tests.

## Initial public source — 2026-10-14

- Native iPhone app with individual Screen Time authorization and app, category, and website selection.
- Native Mac app with an authenticated background service, exact-hostname website rules, and app-process enforcement.
- Add-only persistence, confirmation before additions, and local website autocomplete.
- Configurable developer signing with account-specific settings excluded from source control.
- Regression tests, unsigned build checks, platform documentation, and an MIT license.

This is a source publication, not an App Store, TestFlight, or notarized binary release. See the platform guides for known limitations and required setup.
