# P2-27 Changelog

- Added optional root-only Helper UID/GID expectations to App-bundled trust configuration, preserving decode compatibility for older schema-1 configurations.
- Added App runtime own-CDHash availability/format preflight before opening the production transport.
- Wired App-side Helper peer trust to the provisioned Helper UID/GID expectations.
- Added a pure App/Helper/installer/UID/GID compatibility policy and mismatch tests.
- Updated P2-09 provisioning generation to emit explicit Helper root UID/GID pins.
- Added a read-only macOS final-signature identity audit for App and Helper products.
- Kept all production execution and plugin-association commit gates disabled.
