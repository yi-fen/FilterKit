# P1-08 Revision — App Discovery and Application Icons

## Scope

This revision strengthens the existing P1-08 implementation using the R16 source facts and the supplied AltList-oriented research. It remains read-only: no app bundle is modified, renamed, re-signed, or injected.

## Discovery order

1. Guard against executing the LaunchServices enumeration path when the current executable is `lsd`.
2. Dynamically resolve `LSApplicationWorkspace.defaultWorkspace`.
3. Prefer `enumerateApplicationsOfType:block:` and collect `LSApplicationProxy` objects through its callback for both type values `0` and `1`, matching AltList's implementation.
4. If no proxies are returned, try `allInstalledApplications`.
5. If still empty, try `allApplications`.
6. If LaunchServices is unavailable, fails, or returns no usable inventory, scan immediate `*.app` children under `/var/containers/Bundle/Application/<container UUID>/` and read each app's `Info.plist`.
7. When LaunchServices returns a partial inventory, merge readable directory-scan results by Bundle ID; LaunchServices metadata wins for duplicate IDs.

The directory scanner is a fallback/supplement only. It does not enumerate arbitrary filesystem locations and does not treat an inaccessible directory as an empty installed-app inventory.

## Metadata and classification

The inventory now carries version, build, executable name, icon descriptor, and discovery source (`launchServices` or `directoryScan`). Display-name resolution prefers the proxy's cached `_localizedName`, then `localizedName`, then `CFBundleDisplayName` / `CFBundleName`, and finally Bundle ID. Hidden tags are detected from the proxy's `appTags` values when exposed. Unknown application types remain `unknown`; a `com.apple.` prefix is used only as a conservative system-classification fallback, not as ownership evidence.

## Icon resolution

The row icon is lazy-loaded by `ApplicationIconView` away from the enumeration path:

1. Try proxy-provided `iconData` / `primaryIconData` when exposed as `Data` or `NSData`.
2. Try `iconsDictionary` / `boundIconsDictionary` file names with `resourcesDirectoryURL`.
3. Try Info.plist `CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles`, top-level `CFBundleIconFiles`, and legacy `CFBundleIconFile` candidates.
4. Try `CFBundleIconName` through `UIImage(named:in:compatibleWith:)` using the app bundle.
5. Keep the semantic SF Symbol placeholder if all sources fail.

The descriptor is collected during enumeration; image decoding is deferred until a row appears.

## Error semantics

LaunchServices API absence, workspace absence, enumeration failure, lsd guard, access restriction, and lack of readable inventory are separate error cases. In particular, the UI-facing no-readable-inventory message explicitly says this does not prove that no apps are installed.

## Known validation limits

- LaunchServices selectors, `enumerateApplicationsOfType:block:` callback ABI, application-type numeric value, private proxy selectors, and proxy icon return types are private implementation details. They are dynamically checked and must be verified on the target Dopamine RootHide / Rootless devices and supported iOS versions.
- The current directory fallback is limited to the container app root; it is not a complete source of system apps.
- `UIImage(named:in:compatibleWith:)` is used for `CFBundleIconName`; whether it resolves all target-device `Assets.car` icons must be verified on device.
- This phase does not implement a privileged Helper bridge. Access failures are surfaced distinctly rather than silently reported as an empty list.
- Hidden grouping uses the proxy `appTags` selector when exposed; exact tag availability and semantics remain target-device validation items.
- No `.car` parser dependency is added.
