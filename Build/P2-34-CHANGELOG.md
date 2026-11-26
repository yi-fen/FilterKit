# P2-34 Changelog

- Fixed the FilterKit target build failure where `CachedAppDiscoveryProvider.swift` appeared twice: a stale skeleton copy at the `Sources/` root was picked up by the recursive `- path: Sources` scan alongside the current `Sources/Environment/` copy.
- Replaced the recursive Sources path with the seven explicit first-level subdirectories (`Core`, `DesignSystem`, `Environment`, `Features`, `Localization`, `Persistence`, `Shared`), so any stray Swift file left at the Sources root is no longer compiled into the app target.
- All 122 current Sources Swift files are covered by the explicit subdirectories; App, Resources, Helper target, and test target sources are unchanged.
- Repository-side cleanup still required: delete the stale `Sources/CachedAppDiscoveryProvider.swift` root copy (keep `Sources/Environment/`) and check for any other early skeleton `.swift` left at the Sources root.
- No production write gate, Rootless DEB layout, injection, target-app Bundle modification, or Resources change was added.
