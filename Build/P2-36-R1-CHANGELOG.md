# P2-36-R1 — Source Restoration & Functional Consistency Repair

- Added the `replaceSoftAssociations` intent action and complete desired association-set payload.
- Added Helper-side full-set validation: hard-bound identity is immutable; duplicates/invalid IDs are rejected; existing activation bits cannot be changed from the Plugin page; newly added relationships must be disabled; enabled relationships cannot be removed until disabled from the App detail page.
- Association-only commits preserve the original Filter.plist bytes and update the schema-3 ownership manifest through the existing journaled two-file transaction.
- Added a Save/confirmation entry to the Plugin detail association manager and English/Simplified Chinese strings.
- Added a Host smoke runner and static audit.
- App coordinator and Helper dispatcher write gates remain `false`. The UI save call therefore fails closed until a separately approved release; no real device writes or injection are enabled by this change.
