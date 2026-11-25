# P1-48 Changelog

- App discovery now uses LaunchServices `allInstalledApplications` first and `allApplications` only as fallback.
- Successful LaunchServices discovery no longer triggers a redundant full app-container scan.
- Plugin inventory now prioritizes visibility: dylib-only and plist-only entries remain in the inventory.
- Expensive binary hashing, Mach-O parsing, package ownership queries and manifest verification are deferred from the fast scan.
- Filter plist parsing remains in the fast scan so basic filter targets and App associations remain available.
- Unknown/unverified plugins remain read-only; no management authorization is inferred from visibility.
- Added regression expectations for orphan plist visibility and deferred ownership verification.
