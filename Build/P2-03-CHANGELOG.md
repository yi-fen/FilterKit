# P2-03 Changelog

- Added a read-only App association preview section to plugin details.
- Added installed-App selection, excluding the immutable hard-bound App.
- Added in-memory RootHide ElleKit enable/disable preview actions.
- Added policy checks for FilterKit ownership, management permission, valid pairing, installed target App, and readable regular plist.
- Added before/after Bundle display, planner blockers, and preservation notices.
- Restricted the preview UI to detected RootHide environments and documented that the installed ElleKit revision is not verified.
- Added localized English and Simplified Chinese strings.
- Added unit tests for preview eligibility policy.
- Kept all Helper and mutation release gates closed; no live configuration mutation or injection operation was introduced.
