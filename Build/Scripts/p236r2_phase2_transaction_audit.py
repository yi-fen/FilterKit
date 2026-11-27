#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TX = ROOT / "Sources/Environment/Helper/Execution/HelperPluginFilterConfigurationTransaction.swift"
DISPATCH = ROOT / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift"
COORD = ROOT / "Sources/Environment/Helper/HelperDeploymentCoordinator.swift"
RECOVERY = ROOT / "Sources/Environment/Helper/Runtime/HelperStartupRecoveryCheck.swift"
TX_TEST = ROOT / "Tests/UnitTests/HelperPluginFilterConfigurationTransactionTests.swift"
IPC_TEST = ROOT / "Tests/UnitTests/HelperIPCAndPolicyTests.swift"
IPC = ROOT / "Sources/Core/Models/Helper/HelperIPCModels.swift"

checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

transaction = TX.read_text()
dispatch = DISPATCH.read_text()
coordinator = COORD.read_text()
recovery = RECOVERY.read_text()
tx_tests = TX_TEST.read_text()
ipc_tests = IPC_TEST.read_text()
ipc = IPC.read_text()

phases = ["prepared", "staged", "backedUp", "replacingPlist", "replacingManifest", "committed"]
check("all six journal phases are modeled", all(p in transaction.split("enum Phase: String, Codable {")[1].split("}", 1)[0] for p in phases))
check("journal persists phase transitions", "j.phase = .staged; try save(j,fd)" in transaction and "j.phase = .committed; try save(j,fd)" in transaction)
check("recovery verifies old/new hashes and backup/temp evidence", "if let c,c != old && c != new" in transaction and "if let b,b != old" in transaction and "if let t,t != new" in transaction)
check("non-committed recovery restores originals", "for (dst,old,_,bak,_) in rows where try hash(fd,bak) == old" in transaction)
check("committed recovery preserves committed new files", "if j.phase == .committed" in transaction and "hash(fd,j.manifest) == j.newM" in transaction)
check("crash tests cover every journal phase", all(f".{p}" in tx_tests for p in phases))
check("successful transaction test checks plist byte preservation", "testSuccessfulCommitReplacesManifestAndPreservesPlistBytes" in tx_tests and "Association-only commit must preserve Filter.plist bytes" in tx_tests)
check("tampered destination fails closed", "testRecoveryFailsClosedWhenDestinationContainsForeignBytes" in tx_tests and ".manualIntervention" in tx_tests)
check("recovery idempotence is tested", "testRepeatedRecoveryIsIdempotentAfterJournalCleared" in tx_tests)
host_smoke = (ROOT / "Build/Host/P2-36-R2-Transaction-Smoke.swift").read_text()
check("subprocess SIGKILL recovery smoke exists", "--crash-worker" in host_smoke and "SIGKILL" in host_smoke and "cross-process recovery" in host_smoke)
check("IPC codec uses bounded length-prefixed JSON", "UInt32 big-endian length prefix" in ipc and "maximumFrameBytes" in ipc)
check("soft-association request round-trip is tested", "testSoftAssociationReplacementRequestSurvivesIPCFrameRoundTrip" in ipc_tests and "desiredSoftAssociations" in ipc_tests)
check("IPC trailing bytes are rejected in tests", "testIPCFrameRejectsTrailingBytes" in ipc_tests)
activation_route = dispatch.split("case .appPluginActivationCommitRequest:", 1)[1].split("case .pluginFilterMutationPrepareRequest:", 1)[0]
association_route = dispatch.split("case .pluginFilterMutationCommitRequest:", 1)[1].split("case .deploymentBatchRequest:", 1)[0]
check("dispatcher gates each commit before its transaction invocation", "guard activationCommitExecutionEnabled else" in activation_route and activation_route.index("guard activationCommitExecutionEnabled else") < activation_route.index("transaction.execute(prepared)") and "guard Self.pluginAssociationCommitReleased else" in association_route and association_route.index("guard Self.pluginAssociationCommitReleased else") < association_route.index("transaction.execute(prepared)"))
check("dispatcher commit release gate remains false", "static let pluginAssociationCommitReleased = false" in dispatch)
check("App coordinator release gate remains false", "static let pluginAssociationCommitReleased = false" in coordinator)
check("startup recovery only inspects association journal", "inspectPendingJournal()" in recovery and ".reconcile()" not in recovery)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'} {name}")
print(f"P2-36-R2 Phase 2 static audit: {len(checks)-len(failed)}/{len(checks)} passed")
if failed:
    sys.exit(1)
