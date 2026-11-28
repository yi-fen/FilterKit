from pathlib import Path
root = Path(__file__).resolve().parents[2]
journal = (root / "Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift").read_text()
execution = (root / "Sources/Environment/Helper/Runtime/HelperInstallerTransactionExecution.swift").read_text()
recovery = (root / "Sources/Environment/Helper/Runtime/HelperInstallerCrashRecoveryEngine.swift").read_text()
coordinator = (root / "Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift").read_text()
checks = {
    "journal schema bumped for intent semantics": "self.schemaVersion = 2" in journal and "schemaVersion == 2" in journal,
    "durable pending operation field": "private(set) var pendingOperation: PendingOperation?" in journal,
    "intent event before artifact verification": "case intentVerifyArtifacts" in journal and "intent: .intentVerifyArtifacts" in execution,
    "intent event before previous release preservation": "intent: .intentPreservePreviousRelease" in execution,
    "intent event before staging": "intent: .intentStageRelease" in execution,
    "intent event before activation": "intent: .intentActivateRelease" in execution,
    "intent event before service verification": "intent: .intentVerifyService" in execution,
    "intent event before provisioning commit": "advance(&journal, .intentCommitProvisioning)" in execution,
    "completion requires matching pending intent": "guard pendingOperation == .stageRelease" in journal,
    "chain replay validates pending operation": "expectedPending == pendingOperation" in journal,
    "recovery advances durable completed states": "case .artifactsVerified:" in recovery and "beginNextOperation(next)" in recovery,
    "activation recovery checks active release pointer": "journal activation state disagrees with active release pointer" in recovery,
    "service verified state rejects unjournaled provisioning change": "Provisioning changed without a durable commit intent" in recovery,
    "manual intervention outranks pending operation recommendation": "if journal.state == .manualIntervention" in (root / "Sources/Environment/Helper/Runtime/HelperInstallerRecoveryAssessment.swift").read_text(),
    "interrupted operation avoids blind rollback": "if journal.pendingOperation != nil" in execution,
    "interrupted operation stops service": "try? operations.leaveServiceStopped(prepared)" in execution,
    "service is stopped before rollback": execution.index("try operations.leaveServiceStopped(prepared)") < execution.index("try operations.rollback(prepared"),
    "completion persistence restores durable intent view": "journal = durableIntent" in execution,
    "recovery engine is read-only policy": "struct HelperInstallerCrashRecoveryEngine" in recovery and "func assess(" in recovery,
    "recovery verifies complete artifact hash set": "Set(release.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases)" in recovery and "partial or unexpected staged artifact set" in recovery,
    "recovery requires artifact ownership evidence": "snapshot.artifactOwnershipVerified" in recovery,
    "upgrade recovery validates previous artifact hashes": "snapshot.previousArtifactHashes == expectedPrevious" in recovery,
    "provisioning reconciliation distinguishes target and previous": "snapshot.provisioningEnvelopeSHA256 == targetProvisioningSHA256" in recovery and "snapshot.provisioningEnvelopeSHA256 == previous" in recovery,
    "uncertain state stops service and requires manual": ".stopServiceAndRequireManualIntervention" in recovery,
    "production adapter remains disabled": "var isProductionReady: Bool { false }" in execution,
    "coordinator default installer remains unavailable": "HelperUnavailableRootInstaller()" in coordinator,
    "generated plan remains execution-disabled": "executionEnabled: false" in (root / "Sources/Core/Models/Helper/HelperInstallerProvisioning.swift").read_text(),
}
for name, ok in checks.items(): print(("PASS" if ok else "FAIL") + ": " + name)
if not all(checks.values()): raise SystemExit(1)
print(f"{len(checks)}/{len(checks)} assertions passed")
