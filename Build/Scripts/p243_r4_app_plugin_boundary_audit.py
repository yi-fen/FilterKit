#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
authorizer = (root / "Sources/Environment/Helper/Execution/HelperPluginFilterMutationAuthorizer.swift").read_text()
policy = (root / "Sources/Environment/Helper/Execution/HelperAppPluginActivationTargetPolicy.swift").read_text()
apps = (root / "Sources/Features/Apps/AppsView.swift").read_text()

checks = {
    "APP activation invokes target topology policy": "HelperAppPluginActivationTargetPolicy.validate(" in authorizer,
    "APP activation rejects unassociated target": "throw AuthorizationError.associationMetadataMismatch" in authorizer and "PolicyError.notAssociated" in policy,
    "APP activation cannot append new association": "associations.append(FilterKitManifestSoftAssociation(bundleIdentifier: request.targetBundleIdentifier" not in authorizer,
    "APP activation preserves stored Bundle ID spelling": "let storedBundleIdentifier = associations[index].bundleIdentifier" in authorizer,
    "Plugin page retains explicit association replacement route": "request.action == .replaceSoftAssociations" in authorizer,
    "fixed owner recognized by canonical identity": "if targetKey == ownerKey { return .fixedOwner }" in policy,
    "additional association lookup uses canonical identity": "if key == targetKey { found = true }" in policy,
    "App inventory association projection canonicalized": "HelperBundleIdentifierKey.set(associations.snapshots.flatMap" in apps,
    "App detail owner matching canonicalized": "HelperBundleIdentifierKey.make(owner) == appKey" in apps,
    "App detail soft association matching canonicalized": "HelperBundleIdentifierKey.make($0) == appKey" in apps,
    "App detail filter matching canonicalized": "HelperBundleIdentifierKey.set(bundles).contains(appKey)" in apps,
}
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if not all(checks.values()):
    raise SystemExit(1)
print(f"P2-43-R4 APP/Plugin boundary audit: {len(checks)} assertions passed")
