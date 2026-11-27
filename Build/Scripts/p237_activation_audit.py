#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

models = (ROOT / "Sources/Core/Models/AppPluginActivationModels.swift").read_text()
resolver = (ROOT / "Sources/Environment/Deployment/AppPluginActivationStateResolver.swift").read_text()
apps = (ROOT / "Sources/Features/Apps/AppsView.swift").read_text()
coord = (ROOT / "Sources/Environment/Helper/HelperDeploymentCoordinator.swift").read_text()
dispatch = (ROOT / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift").read_text()
gate = (ROOT / "Sources/Environment/Deployment/PluginToggleReleaseGate.swift").read_text()
preflight = (ROOT / "Sources/Environment/Deployment/PluginActivationPreflight.swift").read_text()
identity = (ROOT / "Sources/Core/Models/PluginIdentityVerificationResult.swift").read_text()
ledger = (ROOT / "Sources/Core/Models/AppPluginActivationPreviewLedger.swift").read_text()
registry = (ROOT / "Sources/Environment/PluginScanRegistry.swift").read_text()
generation = (ROOT / "Sources/Core/Models/PluginScanGenerationTracker.swift").read_text()

check("hard/soft/filter-match association kinds", all(x in models for x in ["case hardBound", "case softAssociated", "case filterMatched"]))
check("independent target bundle ID is part of state", "targetBundleIdentifier: String" in models)
check("Filter config is required for observed state", "filterConfiguration" in resolver and "filterIsReadable = filter?.parseState == .valid" in resolver)
check("soft manifest state cross-check", "manifestState.isEnabled == filterListsTarget" in resolver)
check("mismatch locks preview toggle", "crossCheck == .matched" in resolver and "manifestFilterMismatch" in resolver)
check("global filter is not app-scoped", "globalFilterCannotBeScoped" in resolver)
check("alternate filter dimensions are not misreported", "alternateMatchDimensionsPresent" in resolver)
check("hard-bound activation is not disallowed", "kind != .filterMatched" in resolver and "isHardBound" in resolver)
check("package-manager ownership is rejected and unknown ownership needs Helper proof", "plugin.ownership == .packageManager" in identity and "guard let attestation = plugin.helperIdentityAttestation" in identity)
check("Helper attestation binds Mach-O identity and payload hashes", "attestation.machOIdentitySHA256?.caseInsensitiveCompare" in identity and "attestation.dylibSHA256?.caseInsensitiveCompare" in identity)
check("App Detail separates hard-bound and soft-associated groups", "apps.detail.hard_bound_plugins" in apps and "apps.detail.soft_associated_plugins" in apps)
check("App Detail includes independent Toggle", "Toggle(\"apps.detail.activation_toggle_accessibility\"" in apps)
check("toggle is disabled unless state resolver permits it", ".disabled(!activation.canPreviewToggle)" in apps)
check("toggle preview explicitly performs no writes", "does not write Filter.plist" in (ROOT / "Resources/en.lproj/Localizable.strings").read_text())
check("Helper coordinator release gate remains false", "static let pluginAssociationCommitReleased = false" in coord)
check("Helper dispatcher release gate remains false", "static let pluginAssociationCommitReleased = false" in dispatch)
check("activation production mutation gate remains false", "static let productionMutationReleased = false" in gate)
check("activation preflight mutation gate remains false", "static let mutationReleaseEnabled = false" in preflight)

check("preview key includes plugin and target App", '"\\(pluginID)::\\(bundleID)"' in ledger)
check("preview state clears on scan snapshot change", "values.removeAll()" in ledger and "updateSnapshot" in ledger)
check("scan generation rejects stale refresh results", "scanGeneration.isCurrent(generation)" in registry)
check("scan revision increments for every scan", "snapshotRevision &+= 1" in registry)
check("generation tracker rejects superseded token", "token == current" in generation)
check("identity collisions are rejected", "identityStatus == .uuidCDHashMismatch" in identity and "status: .rejected" in identity)

for name, ok in checks:
    print(("PASS" if ok else "FAIL") + " | " + name)
print(f"P2-37 static audit: {sum(ok for _, ok in checks)}/{len(checks)}")
sys.exit(0 if all(ok for _, ok in checks) else 1)

