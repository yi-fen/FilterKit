#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = {
    "toggle mutation gate closed": ("Sources/Environment/Deployment/PluginToggleReleaseGate.swift", "static let productionMutationReleased = false"),
    "dispatcher execution gate closed": ("Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", "static let executionReleased = false"),
    "dispatcher association gate closed": ("Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift", "static let pluginAssociationCommitReleased = false"),
    "coordinator execution gate closed": ("Sources/Environment/Helper/HelperDeploymentCoordinator.swift", "static let executionReleased = false"),
    "coordinator association gate closed": ("Sources/Environment/Helper/HelperDeploymentCoordinator.swift", "static let pluginAssociationCommitReleased = false"),
    "production backend execution gate closed": ("Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift", "static let executionReleased = false"),
    "preflight explicitly read-only": ("Build/scripts/p230_signed_artifact_preflight.py", '"read_only": True'),
    "preflight never authorizes release": ("Build/scripts/p230_signed_artifact_preflight.py", '"release_authorized": False'),
    "device procedure documents no release": ("Build/P2-30-FIRST-PLUGIN-TOGGLE-PREFLIGHT.md", "No global or per-feature production mutation switch is opened"),
    "changelog records no injection": ("Build/P2-30-CHANGELOG.md", "No deployment, ElleKit mutation, injection, or production release switch was enabled"),
}
failed = 0
for label, (rel, needle) in checks.items():
    ok = needle in (root / rel).read_text()
    print(("PASS" if ok else "FAIL") + " " + label)
    failed += not ok
print(f"{len(checks)-failed}/{len(checks)} passed")
raise SystemExit(1 if failed else 0)
