# P2-33 Changelog

- Added in-flight scan sharing to the cached discovery provider: a single enumeration task is reused by every concurrent caller (prewarm, Apps, Plugins) instead of each launching a separate LaunchServices scan.
- The shared task writes the deduplicated/sorted inventory to the cache once on completion; a failed enumeration leaves the cache untouched for retry.
- Kept TTL cache hits, explicit refresh bypass, snapshot-first first paint, and the existing Provider/ViewModel/View layering unchanged.
- Added a concurrent-call test asserting the underlying source is invoked only once for two simultaneous scans.
- Did not add streaming shell-row rendering, home dashboard data, or any production write gate; no Rootless DEB layout, injection, or target-app Bundle modification was added.
