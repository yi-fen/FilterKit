#!/usr/bin/env python3
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT / p).read_text()
coordinator = read('Sources/Environment/Helper/HelperDeploymentCoordinator.swift')
service = read('Sources/Environment/Helper/HelperAppPluginActivationService.swift')
store = read('Sources/Environment/Deployment/AppPluginActivationOperationStore.swift')
ui = read('Sources/Features/Apps/AppsView.swift')
protocol = read('Sources/Core/Models/Helper/HelperAppPluginActivationProtocol.swift')
tests = read('Tests/UnitTests/HelperAppPluginActivationCoordinatorTests.swift')
strings_en = read('Resources/en.lproj/Localizable.strings')
strings_zh = read('Resources/zh-Hans.lproj/Localizable.strings')
checks = [
 ('APP coordinator sends Prepare with command request ID', 'appPluginActivationPrepareRequest' in coordinator and 'requestID: command.requestID' in coordinator),
 ('Prepare response validates protocol, type and request ID', 'appPluginActivationPrepared' in coordinator and 'response.requestID == command.requestID' in coordinator),
 ('Prepare plan is checked against exact command', 'plan.validates(command: command)' in coordinator),
 ('Commit uses a fresh transport request ID', 'requestID: UUID(), createdAt: now' in coordinator and 'appPluginActivationCommitRequest' in coordinator),
 ('Commit requires explicit user confirmation', 'guard userConfirmed else { throw CoordinatorError.confirmationRequired }' in coordinator),
 ('APP Commit release gate remains closed', 'static let appPluginActivationCommitReleased = false' in coordinator),
 ('Commit proof validates exact command and age', 'proof.validates(command: command, now: Date()' in coordinator),
 ('Service reads current Filter and Manifest bytes', 'Data(contentsOf: URL(fileURLWithPath: plistPath))' in service and 'Data(contentsOf: URL(fileURLWithPath: manifestPath))' in service),
 ('Service hashes exact source bytes', 'SHA256Digest.hex(filterBytes)' in service and 'SHA256Digest.hex(manifestBytes)' in service),
 ('Service binds one plugin and one target App', 'targetBundleIdentifier: activation.targetBundleIdentifier' in service and 'pluginID: pluginID' in service),
 ('Service requires verified FilterKit ownership and management permission', 'plugin.ownership == .filterKit' in service and 'plugin.managementPermission?.canModify == true' in service),
 ('Operation store retains Prepare command and plan', 'let command: HelperAppPluginActivationCommand' in store and 'let plan: HelperAppPluginActivationPlan' in store),
 ('Operation store scopes plan to scan revision', 'pending.snapshotRevision == currentSnapshotRevision' in store and 'snapshotRevision == currentSnapshotRevision' in store),
 ('Snapshot changes invalidate pending operation', 'func invalidatePending' in store and 'self.pending = nil' in store),
 ('Transport failure is treated as unknown outcome, not auto-retried', 'phase = .outcomeUnknown' in store and 'do not retry' in store or 'Never retry' in store),
 ('Successful proof triggers authoritative rescan', 'PluginScanRegistry.shared.refresh()' in store),
 ('APP detail calls Prepare and Commit orchestration', 'operationStore.prepare(plugin: plugin' in ui and 'operationStore.commit(userConfirmed: true' in ui),
 ('UI has explicit confirmation step', '.confirmationDialog(' in ui and 'showingCommitConfirmation' in ui),
 ('UI does not optimistically flip configured state', 'get: { activation.isEnabled ?? false }' in ui and 'setPreview' not in ui),
 ('English and Chinese operation states exist', 'apps.detail.activation_operation_release_closed' in strings_en and 'apps.detail.activation_operation_release_closed' in strings_zh),
 ('Tests cover Prepare, tampered plan, closed Commit and confirmation', all(x in tests for x in ['testPrepareUsesActivationPrepareMessage', 'testPrepareRejectsPlanBoundToDifferentTarget', 'testCommitRemainsClosedBeforeTransportSubmission', 'testCommitRequiresExplicitConfirmation'])),
 ('Proof protocol requires transaction ID only for actual state change', 'command.expectedEnabled != command.desiredEnabled && transactionID != nil' in protocol),
]
failed=[]
for name, ok in checks:
 print(('PASS ' if ok else 'FAIL ') + name)
 if not ok: failed.append(name)
print(f'P2-37-R7 APP activation flow audit: {len(checks)-len(failed)}/{len(checks)}')
if failed: sys.exit(1)
