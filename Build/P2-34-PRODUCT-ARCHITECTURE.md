# P2-34 — Home Dashboard & Product Page Responsibilities

## Product rules locked in this phase

1. **Home** is the device-wide overview: installed App count, discovered plugin count, Filter inventory/health, associated App count, environment summary, and last scan.
2. **Apps** is the only first-time dylib/plist import entry. Import starts from the selected App detail page and is currently read-only preflight/review only.
3. **Plugins** is the plugin library and association-information area. It has no enable/disable controls and no first-time dylib/plist importer. Its file importer accepts only `.filterkitbackup` backup data. Plugin detail shows hard-bound and soft-associated App identities.
4. **Settings** is for low-level environment, Helper, signing identity, and diagnostic controls. Home inventory statistics are not duplicated there.
5. App-scoped enable/disable remains an App-detail responsibility, but production mutation is still fail-closed until the device acceptance and runtime injection evidence are complete.

## Home metrics semantics

- Installed Apps: latest App discovery inventory.
- Discovered plugins: plugin scanner inventory, including third-party/read-only items.
- Filter configurations: scanned plugin items with a paired plist filename.
- Parsed successfully: Filter parser state is `valid`.
- Invalid configurations: Filter parser state is `invalid` or `partial`.
- Associated Apps: unique Bundle IDs found in FilterKit hard-binding and soft-association metadata. This is not a count of processes currently receiving injection.
- Environment status: explicitly distinguishes a validated jailbreak root from a positively identified ElleKit package state. It does not claim that injection is active.

## P2-34 implementation

- Replaced the Home placeholder with a live dashboard backed by the shared App discovery and plugin scan registries.
- Moved plugin inventory statistics out of Settings while retaining low-level ElleKit profile and identity diagnostics there.
- Removed the ordinary dylib/plist importer from the Plugins page.
- Removed plugin-page bulk selection and uninstall controls; the page is now an inventory/detail and backup-data surface, not an activation surface.
- Kept the App-detail dylib/plist file picker as the only first-time plugin import entry.
- Plugin details distinguish hard-bound and soft-associated App Bundle IDs and explicitly direct activation responsibility to the App detail page.
- Backup export and `.filterkitbackup` restore preview remain in Plugins.

## Deliberate limitations

- App-detail file selection is still preflight-only: no payload copy, ownership manifest creation, or ElleKit mutation is performed.
- Plugin association editing UI and durable association commit are not released in P2-34; this phase establishes page boundaries and surfaces current relationship data. The next phase should implement soft-association selection from the plugin/App context, with hard-bound entries locked and Helper commit still gated.
- No per-App enable/disable operation is opened.
- No production release switch was changed.
