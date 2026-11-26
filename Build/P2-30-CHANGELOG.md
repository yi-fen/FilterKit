# P2-30 Changelog

- Removed the scan-side `displayName`/`bundleIdentifier` sort from the LaunchServices provider; dedup and sort are finalized by the cache layer (`deduplicatedAndSorted`) and the display filter (`AppInventoryQuery.filter`), eliminating the redundant second sort.
- Added a non-scanning `currentSnapshot()` to the cached discovery provider that returns the warm inventory without triggering a LaunchServices enumeration.
- Converted the Apps screen load to a two-phase first paint: render the cached snapshot first, then replace it with the background scan/refresh result and load associations afterward. A cold launch with no snapshot still renders the loading state.
- Added an offline test covering snapshot availability after scan and its removal after cache invalidation.
- Kept the `InstalledApp` model, provider protocols, Provider/ViewModel/View layering, and the shared cached provider unchanged; no production write gate, Rootless DEB layout, injection, or target-app modification was added.
- Left in-flight scan dedup and streaming shell-row rendering for later review; cold-launch no-snapshot and in-flight scenarios still fall back to the loading state.
