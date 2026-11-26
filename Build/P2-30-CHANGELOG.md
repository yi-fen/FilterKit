# P2-30 Changelog

- Added a macOS-only, read-only signed App/Helper artifact preflight.
- Captures codesign verification output, CDHashes, signed identifiers, Team IDs, App bundle identifier, and embedded Helper AppTrust JSON.
- Fails closed when run off macOS, when artifacts are missing, when signatures fail, or when the embedded trust JSON is absent/invalid.
- Added the first-plugin-toggle device procedure and explicit evidence limitations.
- No deployment, ElleKit mutation, injection, or production release switch was enabled.
