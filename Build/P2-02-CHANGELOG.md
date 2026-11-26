# P2-02 Changelog

- Added a RootHide ElleKit 1.2-3-specific in-memory Filter.plist strategy planner.
- Modeled OR semantics across Bundles, Classes, and Executables; CoreFoundationVersion remains a gate.
- Added strict fail-closed checks for RootHide's nested Filter dictionary and recognized field types.
- Added conservative per-App disable preview blocking when Classes or Executables remain active.
- Preserved unknown root/filter keys and CoreFoundationVersion in generated preview data.
- Added unit tests covering safe and blocked plans.
- No device files, Helper execution gates, or mutation release flags were changed.
