# P2-42-R10 — Compact Plugin Inventory

## Product/UI decisions

- Plugin rows present a compact four-part hierarchy: plugin name, associated Apps, management type/injection summary, and source.
- The Fixed Owner App is the default/first App shown. At most two App names are rendered; additional associations are represented by a localized `+N` suffix.
- Management type is `Standalone Plugin` when no persisted App association exists, otherwise `App-associated Plugin`.
- Per-App injection remains independent. The row summarizes enabled/disabled/unknown counts rather than expanding every App into a separate line.
- The existing top-right icon button remains a direct two-state toggle; no menu was introduced.
- The alternate scope includes FilterKit-owned plugins with at least one App association, whether all associated Apps are enabled, disabled, or mixed. It excludes standalone FilterKit plugins and non-FilterKit plugins.

## Safety and data behavior

- No association topology, Fixed Owner identity, Additional App Association, or per-App enabled bit is modified.
- Injection status remains a conservative read-only comparison between the observed Filter.plist and persisted association state. Ambiguous/unusable Filter.plist data is shown as unknown.
- The Plugins page continues to display only complete dylib + Filter.plist pairs.
- No scanner, cache, polling loop, Helper authorization, or production mutation Gate was added or changed.
