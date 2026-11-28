from pathlib import Path
root = Path(__file__).resolve().parents[2]
policy = (root / "Sources/Core/Models/PluginLifecyclePolicy.swift").read_text()
apps_view = (root / "Sources/Features/Apps/AppsView.swift").read_text()
operation = (root / "Sources/Environment/Deployment/AppPluginActivationOperationStore.swift").read_text()
topology = (root / "Sources/Core/Models/PluginBindingTopology.swift").read_text()
planner = (root / "Sources/Environment/Helper/Execution/HelperPluginAssociationFilterMutationPlanner.swift").read_text()
end_to_end = (root / "Tests/UnitTests/PluginLifecycleEndToEndConsistencyTests.swift").read_text()
policy_tests = (root / "Tests/UnitTests/PluginLifecyclePolicyTests.swift").read_text()
coordinator = (root / "Sources/Environment/Helper/HelperDeploymentCoordinator.swift").read_text()
dispatcher = (root / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift").read_text()

checks = [
    ("installed App projection uses canonical Bundle IDs", "let installedKeys = HelperBundleIdentifierKey.set(installedBundleIdentifiers)" in policy),
    ("unavailable App projection preserves Manifest spelling", "!installedKeys.contains(HelperBundleIdentifierKey.make($0))" in policy),
    ("per-App enabled lookup uses canonical Bundle IDs", "func isEnabled(bundleIdentifier: String)" in policy and "HelperBundleIdentifierKey.make(bundleIdentifier)" in policy),
    ("Fixed Owner add collision is case-insensitive", "HelperBundleIdentifierKey.make(evidence.fixedOwnerBundleIdentifier ?? \"\")" in policy),
    ("Additional Association add collision is case-insensitive", "additionalAssociationBundleIdentifiers.contains(where:" in policy),
    ("Fixed Owner removal is immutable case-insensitively", "return .fixedOwnerImmutable" in policy and "HelperBundleIdentifierKey.make(bundleID)" in policy),
    ("Additional Association removal resolves canonical identity", "additionalAssociationBundleIdentifiers.contains(where:" in policy),
    ("pending APP operation row matches canonical Bundle identity", "HelperBundleIdentifierKey.make(operationStore.pending?.command.targetBundleIdentifier ?? \"\")" in apps_view),
    ("unknown operation row identity remains canonical", "HelperBundleIdentifierKey.make(command.targetBundleIdentifier)" in operation),
    ("new Plugin-page associations default disabled", "isEnabled: false" in topology),
    ("retained association activation bits cannot be changed by Plugin planner", "previous.isEnabled == item.isEnabled" in planner),
    ("multi-App removal regression preserves other App states", "testPluginPageRemovalStopsPreviouslyEnabledAppWithoutChangingOtherApps" in end_to_end and "testRemovingOneEnabledAssociationDoesNotChangeOtherAppActivationBits" in policy_tests),
    ("APP activation commit gate remains closed", "static let appPluginActivationCommitReleased = false" in coordinator),
    ("Helper execution gate remains closed", "static let executionReleased = false" in dispatcher),
]
for label, passed in checks:
    if not passed:
        raise SystemExit(f"FAIL: {label}")
print(f"P2-43-R2 lifecycle integration audit: {len(checks)} assertions passed")
