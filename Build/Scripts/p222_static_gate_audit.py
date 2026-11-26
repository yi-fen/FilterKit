#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
ledger = (root / 'Sources/Environment/Helper/Execution/HelperDeploymentIdempotencyLedger.swift').read_text()
dispatch = (root / 'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
tests = (root / 'Tests/UnitTests/HelperDeploymentBatchProtocolTests.swift').read_text()
doc = (root / 'Build/P2-22-CHANGELOG.md').read_text()
checks = {
 'batch ledger binds digest and operation IDs': 'let digest: String' in ledger and 'let requestIDs: [UUID]' in ledger,
 'ledger is thread safe': 'NSLock()' in ledger,
 'matching in-progress retry is rejected': 'deploymentBatchInProgress' in dispatch and '.existing(.inProgress)' in dispatch,
 'indeterminate retry is distinguished': 'deploymentBatchOutcomeUnknown' in dispatch and '.existing(.indeterminate)' in dispatch,
 'batch ID conflict is rejected': 'deploymentBatchConflict' in dispatch and '.conflict' in dispatch,
 'batch request bypasses generic envelope replay guard': 'if envelope.messageType != .deploymentBatchRequest' in dispatch,
 'ledger reserves operation IDs across batches': 'operationOwners[$0] == nil' in ledger and 'operationOwners[requestID] = batchID' in ledger,
 'unit tests cover digest and operation binding': 'testDeploymentIdempotencyLedgerBindsBatchDigestAndOperationIDs' in tests,
 'dispatcher does not reserve batches before release gate': 'testDispatcherDoesNotReserveBatchBeforeExecutionGateOpens' in tests,
 'ledger restart limitation documented': 'process-local only' in doc and 'exactly-once' in doc,
 'production gates remain closed': all('static let '+name+' = false' in (root / path).read_text() for path,name in [
  ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','executionReleased'),
  ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','pluginAssociationCommitReleased'),
  ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','executionReleased'),
  ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','pluginAssociationCommitReleased'),
  ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift','executionReleased')]),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} checks passed')
raise SystemExit(0 if all(checks.values()) else 1)
