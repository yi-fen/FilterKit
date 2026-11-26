# P1-50 Changelog

- Added a three-line plugin row: plugin name; dylib filename plus paired/unpaired status; associated App names plus source classification.
- Added hard-bound / soft-associated App display from a size-bounded FilterKit manifest metadata projection without marking the manifest verified.
- Added non-FilterKit App association display by matching Filter bundle IDs and Executable names against the installed-App inventory.
- Added global wildcard and unmatched-target presentation.
- Shared the 60-second cached LaunchServices inventory between Apps and Plugins screens.
- Removed a duplicate plist decode from fast plugin inventory.
- Removed unused DPKG ownership and full-manifest verification helpers from the fast scanner; authorization remains unchanged and conservative.
- Preserved read-only scanning, symlink/canonical-path checks, lazy icons, and deferred Mach-O/hash/DPKG verification.
