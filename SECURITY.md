# Security policy

JustThirty is preparing its first public release. Security fixes target the current `main` branch; there is no long-term support or response-time guarantee.

## Report a vulnerability privately

Use GitHub's [private vulnerability reporting](https://github.com/FarzamHejaziK/Just30/security/advisories/new). Include the affected commit, platform, reproduction steps, impact, and a minimal proof of concept that does not disclose private data. Do not post exploitable details in public issues before the maintainer has had a chance to investigate.

Never send Apple credentials, certificates/private keys, provisioning profiles, UDIDs, personal block lists, full hosts files, or unredacted diagnostic archives.

## Security boundary

On Mac, a privileged service owns the list, daily budget, and hosts changes. The app and service authenticate each other by Apple code-signing anchor, team ID, and exact identifier. The interface exposes snapshots, additions, and bounded start/pause operations. It exposes no list deletion, budget reset, arbitrary commands, or unlimited unlock. A client-authentication bypass, arbitrary file write, arbitrary process termination, data corruption, or privilege escalation is a security issue.

The signed app is a trusted client. An administrator who controls the machine or the signing key can change its behavior. The `--unsigned` build is for compilation and UI preview; it does not provide the authenticated production service.

Revoking iPhone Screen Time access, disabling a Mac background service as administrator, and the documented hosts/browser limitations are outside JustThirty's tamper-resistance guarantees. They can still warrant documentation or usability improvements.

See [architecture](docs/architecture.md) and [privacy](docs/privacy.md) for more detail.
