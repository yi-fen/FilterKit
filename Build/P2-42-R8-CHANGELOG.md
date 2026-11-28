# P2-42-R8 Changelog

## Plugin list presentation
- Plugin list now only presents complete, paired dylib + Filter.plist records.
- Removed paired/unpaired status text from plugin rows and plugin detail.
- Orphan and invalid records remain in the read-only scan result for diagnostics; they are not promoted into the plugin list.
- Row hierarchy is now: plugin display name, dylib filename, resolved Filter.plist load target / association names, then source.
- Unknown source remains `来源：未知` / `Source: unknown`.

## Filter.plist compatibility and load-target safety
- Continue supporting both a nested `Filter` dictionary and a top-level filter dictionary.
- Recognize target keys case-insensitively.
- Accept a single string or an array of strings for `Bundles`, `Executables`, and `Classes`.
- Ignore malformed non-string array entries while retaining valid entries and marking the parse partial.
- Detect case-variant duplicate keys and mark the parse partial; duplicate `Bundles` or `Executables` keys force load-target status to unknown.
- Missing both `Bundles` and `Executables` is not proof of an independent plugin. The parser marks it partial.
- A plugin is called independent only when target fields are explicitly present, parse is valid, and both target lists are empty.
- Unknown/vendor keys are preserved as unknown metadata; their semantics are not guessed.
- Original plist bytes are never rewritten.

## Safety / architecture
- No second plugin scanner or additional App inventory/cache was introduced.
- App display names continue to use the existing `PluginAppDisplayIndex`.
- Manifest association hints are not used as proof of Filter.plist load targets.
- Production mutation gates remain unchanged and closed.
