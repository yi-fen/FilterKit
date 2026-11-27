#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
policy = (root / "Sources/Environment/Helper/HelperPluginAssociationMutationPolicy.swift").read_text()
tests = (root / "Tests/UnitTests/HelperPluginAssociationMutationPolicyTests.swift").read_text()
coordinator = (root / "Sources/Environment/Helper/HelperDeploymentCoordinator.swift").read_text()
dispatcher = (root / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift").read_text()
plugins = (root / "Sources/Features/Plugins/PluginsView.swift").read_text()
checks = [
    ("Policy rejects invalid bundle identifiers", "invalidBundleIdentifier" in policy),
    ("Policy rejects duplicate associations", "duplicateAssociation" in policy),
    ("Hard-bound App is immutable", "hardBoundImmutable" in policy),
    ("New associations must start disabled", "else if enabled" in policy and "activationStateIsAppDetailOnly" in policy),
    ("Existing activation bits cannot be changed in Plugins page", "prior == enabled" in policy),
    ("Enabled relationships must be disabled in App detail before removal", "enabledAssociationMustBeDisabledFirst" in policy),
    ("Association set is bounded to 512", "desired.count <= 512" in policy),
    ("Policy returns deterministic ordering", "desired.sorted" in policy),
    ("Tests cover new disabled association", "testNewAssociationMustStartDisabled" in tests),
    ("Tests reject new enabled association", "testNewEnabledAssociationIsRejected" in tests),
    ("Tests preserve existing activation bit", "testExistingActivationBitMustBePreserved" in tests),
    ("Tests reject removing enabled association", "testEnabledAssociationCannotBeRemovedBeforeAppDetailDisablesIt" in tests),
    ("Tests allow removing disabled association", "testDisabledAssociationCanBeRemoved" in tests),
    ("Tests reject hard-bound and duplicate IDs", "testHardBoundAndDuplicatesAreRejected" in tests),
    ("Tests verify stable sorting", "testOutputIsSorted" in tests),
    ("Coordinator production commit gate remains closed", "static let pluginAssociationCommitReleased = false" in coordinator),
    ("Helper dispatcher production commit gate remains closed", "static let pluginAssociationCommitReleased = false" in dispatcher),
    ("Plugins page has no activation controls", "setSoftEnabled" not in plugins),
]
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
print(f"P2-36 association policy audit: {len(checks)-len(failed)}/{len(checks)} passed")
if failed: sys.exit(1)
