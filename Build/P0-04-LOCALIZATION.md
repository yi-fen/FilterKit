# P0-04 — Localization Module

## Supported languages

- Simplified Chinese: `zh-Hans`
- English: `en`

## Language selection behavior

1. On first launch, the preference defaults to `system`.
2. In `system` mode, a Chinese system language (`zh-*`) resolves to `zh-Hans`.
3. All other system languages resolve to English.
4. A manual Chinese or English selection is persisted in `UserDefaults` under `filterkit.language.selection`.
5. The root app injects the resolved locale into SwiftUI's environment. Changing the published selection updates that environment and refreshes localized SwiftUI text without an app restart.

## Adding UI text

All user-facing text must use localization keys, not hard-coded display strings. Add every new key to both:

- `Resources/en.lproj/Localizable.strings`
- `Resources/zh-Hans.lproj/Localizable.strings`

Run `Build/Scripts/verify-localizations.py` to check syntax, duplicate keys, and key parity.

## Scope and verification

This phase completes the language preference and runtime locale plumbing using the existing `.strings` catalogs. It does not yet migrate to String Catalog (`.xcstrings`). Static catalog validation is available; runtime switching and persistence still require Xcode/simulator/device verification on macOS.
