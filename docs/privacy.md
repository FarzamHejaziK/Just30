# Privacy

OneWay's application code has no hosted backend, account system, analytics SDK, advertising SDK, telemetry endpoint, or cloud synchronization. Website suggestions are a bundled local catalog; typing a query does not send it to a search engine or visit that site.

## Stored on your devices

The iPhone app stores opaque Apple selection tokens and explicitly added website domains in its own container. The Mac stores selected app names, bundle identifiers, paths, and website hostnames in a root-owned file. The Mac interface also caches the last-known list in user defaults so it can show it when the helper is unavailable.

The Mac service examines user-process executable paths and enclosing app identities to find selected apps. It does not record a general application-usage history. Hosts-based blocking does not require reading page content. The service writes enforcement errors to the local system log; diagnostics can contain local paths or hostnames.

Apple controls Screen Time authorization, signing, and other operating-system services. Builds may contact Apple for signing/provisioning or timestamping. GitHub receives normal repository and CI traffic. Those services have their own policies; they are not a OneWay cloud backend.

## Publishing and support

The repository excludes local signing settings, credentials, profiles, device IDs, generated builds, runtime block lists, and hosts backups. Before sharing screenshots or logs, check them for personal sites, app names, account information, and device details. A public GitHub issue is visible to everyone.

There is no in-app data-removal interface because the product's normal policy is add-only. A device owner with the appropriate operating-system or administrator access can still perform maintenance. See the platform guides before changing or uninstalling an installation with active restrictions.
