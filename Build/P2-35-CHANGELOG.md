# P2-35 Changelog

- Replaced the Plugins-page association placeholder with a soft-association checklist in plugin detail.
- Hard-bound App is visible, immutable, and excluded from the selectable App list.
- Added authorization checks for FilterKit ownership, management permission, valid pairing, valid plugin identity, and conflict-free ownership/identity.
- Added local association draft editing, stale-association removal, and a change preview.
- New soft associations are inactive by default; association and activation remain separate.
- Removed the old Plugins-page enable/disable preview and Helper commit UI implementation.
- Kept all persistent writes and production release gates closed.
