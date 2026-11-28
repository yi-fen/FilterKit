#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

scanner = read("Sources/Environment/ReadOnlyPluginScanner.swift")
ui = read("Sources/Features/Plugins/PluginsView.swift")
provider = read("Sources/Environment/DpkgFileOwnershipProvider.swift")
models = read("Sources/Core/Models/PluginScanModels.swift")
registry = read("Sources/Environment/PluginScanRegistry.swift")
profiles = read("Sources/Environment/Profiles/ElleKitProfileRegistry.swift")
zh = read("Resources/zh-Hans.lproj/Localizable.strings")
en = read("Resources/en.lproj/Localizable.strings")

checks = {
    "Filter.plist remains read-only parsed": "PluginFilterConfiguration.parse(data)" in scanner,
    "third-party targets are projected from Filter.plist": "PluginTargetDisplay.resolve(plugin)" in ui,
    "unrecognized target is not described as standalone": "not assumed standalone" in en and "不代表独立插件" in zh,
    "dylib filename removed from compact list row": 'Text(fileName).font(.caption)' not in ui,
    "disclosure NavigationLink removed from plugin list": "NavigationLink(destination: PluginScanDetailView" not in ui,
    "detail remains accessible through a sheet": ".sheet(item: $selectedPlugin)" in ui,
    "RootHide nested dpkg database root is considered": 'appendingPathComponent("var/jb"' in provider,
    "package version and evidence are retained": "packageVersion: packageVersion" in scanner and "packageEvidenceSource" in models,
    "Mach-O Team ID is retained and displayed": "machOTeamIdentifiers" in scanner and "machOTeamIdentifiers" in models and "plugins.macho.team_identifier" in ui,
    "aggregate inventory diagnostics include provenance": "package_manager_owned_count" in registry and "filter_bundle_target_count" in registry,
    "ElleKit profile remains unverified without pinned fingerprint": "binaryFingerprints: []" in profiles,
}

for label, passed in checks.items():
    print(("PASS" if passed else "FAIL") + "  " + label)

# Localization key parity and duplicate check.
def keys(text):
    return re.findall(r'^\s*"((?:\\.|[^"\\])+)"\s*=', text, re.MULTILINE)

for label, content in (("en", en), ("zh-Hans", zh)):
    found = keys(content)
    duplicates = sorted({key for key in found if found.count(key) > 1})
    if duplicates:
        checks[f"{label} localization has no duplicate keys"] = False
        print("FAIL  " + label + " duplicate localization keys: " + ", ".join(duplicates[:10]))
    else:
        print("PASS  " + label + f" localization keys unique ({len(found)})")

if set(keys(en)) != set(keys(zh)):
    checks["localization key parity"] = False
    print("FAIL  English/Simplified Chinese localization key parity")
else:
    print("PASS  English/Simplified Chinese localization key parity")

failed = [label for label, passed in checks.items() if not passed]
print(f"R4.4 static audit: {len(checks) - len(failed)}/{len(checks)} passed")
sys.exit(1 if failed else 0)
