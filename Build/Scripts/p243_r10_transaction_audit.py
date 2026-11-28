from pathlib import Path
root = Path(__file__).resolve().parents[2]
execution = (root / "Sources/Environment/Helper/Runtime/HelperInstallerTransactionExecution.swift").read_text()
journal = (root / "Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift").read_text()
coordinator = (root / "Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift").read_text()
checks = {
    "journal persistence abstraction": "protocol HelperInstallerJournalPersisting" in execution,
    "production durable journal conformance": "extension HelperInstallerDurableJournalStore: HelperInstallerJournalPersisting" in execution,
    "no production operation backend": "HelperUnavailableInstallerTransactionOperator" in execution,
    "journaled adapter remains production-disabled": "struct HelperJournaledRootInstallerAdapter" in execution and "var isProductionReady: Bool { false }" in execution,
    "coordinator receives typed commit outcome": "HelperInstallerProvisioningCommitResult" in (root / "Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift").read_text(),
    "artifact verification before stage": execution.index("operations.verifyArtifacts") < execution.index("operations.stageRelease"),
    "preserve before upgrade stage": execution.index("operations.preservePreviousRelease") < execution.index("operations.stageRelease"),
    "activate before service verify": execution.index("operations.activateRelease") < execution.index("operations.verifyActivatedService"),
    "provisioning commit after service verify": execution.index("operations.verifyActivatedService") < execution.index("commitProvisioning()"),
    "rollback on rejected commit or operation failure": "operations.rollback" in execution,
    "leave service stopped after rollback": "operations.leaveServiceStopped" in execution,
    "indeterminate commit enters manual intervention": "case .indeterminate" in execution and "requireManualIntervention" in execution,
    "service verified rollback transition": "case (.prepared, .beginRollback)" in journal and "case .beginRollback:" in journal,
    "service verified manual transition": "(.activated, .requireManualIntervention)" in journal and "(.rollbackRequired, .requireManualIntervention)" in journal,
    "generated plans remain disabled": "executionEnabled: false" in (root / "Sources/Core/Models/Helper/HelperInstallerProvisioning.swift").read_text(),
    "default installer remains unavailable": "HelperUnavailableRootInstaller()" in coordinator,
    "operator boolean is not silently treated as production credential": "operatorApproved: operatorApproved" in coordinator,
}
for name, ok in checks.items(): print(("PASS" if ok else "FAIL") + ": " + name)
if not all(checks.values()): raise SystemExit(1)
print(f"{len(checks)}/{len(checks)} assertions passed")
