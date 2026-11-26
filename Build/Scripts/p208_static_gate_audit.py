#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = {
    "App commit gate closed": ("Sources/Environment/Helper/HelperDeploymentCoordinator.swift", "static let pluginAssociationCommitReleased = false"),
    "Helper commit gate closed": ("Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", "static let pluginAssociationCommitReleased = false"),
    "App invokes service from confirmation": ("Sources/Features/Plugins/PluginsView.swift", "HelperPluginAssociationCommitService.production()"),
    "explicit confirmation passed": ("Sources/Features/Plugins/PluginsView.swift", "userConfirmed: true"),
    "signed trust resource required": ("Sources/Environment/Helper/HelperPluginAssociationCommitService.swift", "FilterKit-Helper-AppTrust"),
    "receipt identity checked": ("Sources/Features/Plugins/PluginsView.swift", "receipt.targetBundleIdentifier == selectedBundleIdentifier"),
    "intent-only request hashes": ("Sources/Environment/Helper/HelperPluginAssociationCommitService.swift", "expectedManifestSHA256: SHA256Digest.hex(manifestBytes)"),
}
failed = []
for label, (file, needle) in checks.items():
    ok = needle in (root / file).read_text()
    print(("PASS" if ok else "FAIL") + " " + label)
    if not ok: failed.append(label)
print(f"{len(checks)-len(failed)}/{len(checks)} checks passed")
raise SystemExit(bool(failed))
