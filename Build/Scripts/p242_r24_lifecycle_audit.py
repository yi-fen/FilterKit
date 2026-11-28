from pathlib import Path

root = Path(__file__).resolve().parents[2]
ledger = (root / "Sources/Environment/Helper/Execution/HelperAppPluginActivationTransactionLedgerStore.swift").read_text()
operation = (root / "Sources/Environment/Deployment/AppPluginActivationOperationStore.swift").read_text()
command = (root / "Sources/Core/Models/Helper/HelperAppPluginActivationProtocol.swift").read_text()
dispatcher = (root / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift").read_text()
view = (root / "Sources/Features/Apps/AppsView.swift").read_text()
tests = (root / "Tests/UnitTests/HelperAppPluginActivationTransactionLedgerStoreTests.swift").read_text()

assert '.filterkit-app-activation-ledger.lock' in ledger
assert 'flock(fd, LOCK_EX)' in ledger
assert 'capacityReached' in ledger and 'records.count < maximumRecords' in ledger
assert 'validatesForRecoveryHint()' in command
assert 'pendingUnknown.v1' in operation
assert 'restored_pending_helper_verification' in operation
assert 'persistRecoveryHint(pending.command)' in operation
assert 'dispatchSerializationLock.lock()' in dispatcher
assert 'dismissScanObservation()' in view
assert 'guard helperResolved else { return }' in operation
assert 'static let executionReleased = false' in dispatcher
assert 'testCapacityFailsClosedWithoutEvictingExistingCommand' in tests
print('R24 lifecycle audit: 12 assertions passed')
