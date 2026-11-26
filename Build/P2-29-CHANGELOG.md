# P2-29 Changelog

- Added a detached, failure-tolerant `prewarm()` to the shared cached App discovery provider.
- Warmed the installed-App inventory from the root `MainTabView` task so the Apps/Plugins screens read a warm cache instead of blocking on the first LaunchServices enumeration.
- Externalized RootHide DEB package identity, architecture, payload layout, register path, dependencies, and control metadata to `Build/Config/DEB/roothide.env`; `package-deb.sh` sources the profile and validates profile/App consistency.
- Added a workflow pre-check that rejects Rootless paired with DEB/Both before build, and clarified the form descriptions and `ci-build.sh` rejection message.
- Kept the existing Provider/ViewModel/View layering, the shared cached provider, the single-read `Info.plist` path, and the lazy icon decode unchanged.
- Did not add two-stage shell-row rendering, in-flight scan dedup, or any Rootless DEB layout; no production write gate was opened.
