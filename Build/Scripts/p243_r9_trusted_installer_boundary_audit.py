#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
coordinator = (root / "Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift").read_text()
release_set = (root / "Sources/Environment/Helper/Installer/HelperRootReleaseSet.swift").read_text()
lock = (root / "Sources/Environment/Helper/Runtime/HelperReleaseAcceptanceLock.swift").read_text()
plan = (root / "Sources/Core/Models/Helper/HelperInstallerProvisioning.swift").read_text()
gate = (root / "Sources/Environment/Helper/Runtime/HelperInstallerExecutionGate.swift").read_text()
loader = (root / "Sources/Environment/Helper/Runtime/HelperSignedReleaseRuntimeLoader.swift").read_text()
tests = (root / "Tests/UnitTests/HelperTrustedInstallerCoordinatorTests.swift").read_text()
checks = {
    "signed provisioning envelope decoded": "HelperSignedProvisioningManifest.self" in coordinator,
    "Ed25519/key lifecycle verifier invoked": "verifier.verify(envelope)" in coordinator,
    "bundle root bound to closed plan": "bundle.jbRootPath == plan.jbRootPath" in coordinator,
    "exact three-artifact release verifier invoked": "HelperRootReleaseSet().verify" in coordinator,
    "journal initialized and chain validated": "HelperInstallerTransactionJournal(action:" in coordinator and "journal.validateChain()" in coordinator,
    "R8 trusted store commit callback is part of adapter transaction": "commitProvisioningConsistently(prepared, using: trustedProvisioningStore)" in coordinator and "commitProvisioning: () throws -> HelperInstallerProvisioningCommitResult" in coordinator and "return .committed" in coordinator and "return .indeterminate" in coordinator,
    "provisioning commit error is reconciled before rollback decision": "store.recoverPendingTransaction()" in coordinator and "store.loadTrustedBaseline()" in coordinator,
    "indeterminate provisioning commit has explicit manual-intervention state": "provisioningCommitIndeterminate" in coordinator and "provisioningCommitRejected" in coordinator,
    "execution gate checked before adapter": coordinator.index("gate.blockReason") < coordinator.index("rootInstaller.execute(prepared)"),
    "default root installer remains unavailable": "HelperUnavailableRootInstaller()" in coordinator and "var isProductionReady: Bool { false }" in coordinator,
    "execution remains disabled by generated plans": "executionEnabled: false" in plan and "plan.executionEnabled" in gate,
    "release manifest schema validated against current model": "HelperDeploymentManifest.currentSchemaVersion" in release_set,
    "release manifest pins app and helper identity": "bundle.appCDHash" in release_set and "bundle.helperCDHash" in release_set and "bundle.teamIdentifier" in release_set,
    "shared persistent lock used by installer": "HelperReleaseAcceptanceLock.withLock" in coordinator,
    "startup acceptance uses same lock": "HelperReleaseAcceptanceLock.withLock" in loader,
    "cross-process lock waits rather than nonblocking race": "flock(fd, LOCK_EX)" in lock and "LOCK_EX | LOCK_NB" not in lock,
    "no shell command execution in coordinator": "Process()" not in coordinator and "launchctl" not in coordinator and "system(" not in coordinator,
    "tests cover disabled gate and malformed envelope": "testExecutionGateBlocksGeneratedPlanEvenWithAllEvidence" in tests and "testMalformedProvisioningEnvelopeIsRejectedBeforePreparation" in tests,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + " " + name)
print(f"RESULT {len(checks)-len(failed)}/{len(checks)}")
raise SystemExit(1 if failed else 0)
