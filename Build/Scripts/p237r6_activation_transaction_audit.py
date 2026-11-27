#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
dispatcher = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
protocol = (root/'Sources/Core/Models/Helper/HelperAppPluginActivationProtocol.swift').read_text()
transaction = (root/'Sources/Environment/Helper/Execution/HelperPluginFilterConfigurationTransaction.swift').read_text()
runtime = (root/'Sources/Environment/Helper/Runtime/HelperRuntime.swift').read_text()
tests = (root/'Tests/UnitTests/HelperAppPluginActivationProtocolTests.swift').read_text()
checks = {
 'commit payload is plan-bound': 'HelperAppPluginActivationCommitRequest' in protocol and 'preparedPlan.validates(command: command)' in protocol,
 'commit gets a fresh replay-guard request ID': 'requestID != command.requestID' in protocol and 'commit.requestID == envelope.requestID' in dispatcher,
 'commit decoder uses wrapper': 'decodeAppPluginActivationCommit(payload)' in dispatcher,
 'fresh helper authorization at commit': 'authorizer.prepare(command.makeMutationRequest(), now: now)' in dispatcher,
 'fresh plan compared exactly': 'freshPlan == commit.preparedPlan' in dispatcher,
 'fresh actual enabled state checked': 'actualEnabled == command.expectedEnabled' in dispatcher,
 'fresh before/after hashes bound': 'filterBeforeSHA256: filterBefore' in dispatcher and 'manifestAfterSHA256: manifestAfter' in dispatcher,
 'durable pre-commit audit barrier': 'app_plugin_activation_commit_authorized' in dispatcher,
 'two-file transaction executed': 'transaction.execute(prepared)' in dispatcher,
 'transaction changes only Filter and manifest': 'let rows = [(j.plist,j.oldP,j.newP,j.pBak,j.pTmp),(j.manifest,j.oldM,j.newM,j.mBak,j.mTmp)]' in transaction,
 'journal stages both files': 'case prepared, staged, backedUp, replacingPlist, replacingManifest, committed' in transaction,
 'transaction checks original bytes and hashes': 'read(fd, plist, 4*1024*1024) == p.previousPlistData' in transaction and 'read(fd, manifest, 64*1024) == p.previousManifestData' in transaction,
 'transaction stages and verifies replacement hashes': 'hash(fd,j.pTmp) == j.newP' in transaction and 'hash(fd,j.mTmp) == j.newM' in transaction,
 'transaction has rollback reconciliation': 'reconcileLocked(fd)' in transaction,
 'proof generated from transaction receipt': 'filterSHA256: receipt.plistSHA256' in dispatcher and 'transactionID: receipt.transactionID' in dispatcher,
 'proof validates requested command': 'proof.validates(command: command' in dispatcher,
 'no-op proof has no transaction id': 'transactionID: nil, completedAt: now' in dispatcher,
 'production gate remains false': 'static let pluginAssociationCommitReleased = false' in dispatcher,
 'runtime does not enable test execution flag': 'activationCommitExecutionEnabled:' not in runtime,
 'test-only execution switch defaults false': 'activationCommitExecutionEnabled: Bool = false' in dispatcher,
 'commit request tests plan tampering': 'testCommitRequestMustCarryExactPreparedPlan' in tests,
 'commit malformed payload test': 'testAppPluginActivationCommitRequiresBoundPreparePlan' in (root/'Tests/UnitTests/HelperRequestDispatcherTests.swift').read_text(),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'RESULT {len(checks)-len(failed)}/{len(checks)}')
raise SystemExit(1 if failed else 0)
