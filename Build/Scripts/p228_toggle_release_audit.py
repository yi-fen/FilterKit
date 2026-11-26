#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, ok): checks.append((name, bool(ok)))
gate = (root/'Sources/Environment/Deployment/PluginToggleReleaseGate.swift').read_text()
strategy = (root/'Sources/Environment/Deployment/EnableDisableStrategy.swift').read_text()
tests = (root/'Tests/UnitTests/PluginToggleReleaseGateTests.swift').read_text()
dispatcher = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
coordinator = (root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text()
backend = (root/'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift').read_text()
check('P2-28 introduces a dedicated per-App toggle release gate', 'enum PluginToggleReleaseGate' in gate)
check('production toggle release remains explicitly closed', 'static let productionMutationReleased = false' in gate)
check('device-validated enable and disable strategy is mandatory', 'if !evidence.strategy.permitsMutation' in gate and 'deviceValidated' in strategy)
check('Helper identity, recovery and audit are independent barriers', all(x in gate for x in ['helperIdentityValidated', 'recoveryJournalClean', 'auditSinkWritable']))
check('FilterKit ownership and paired payload verification are mandatory', all(x in gate for x in ['pluginOwnershipVerified', 'pluginPairVerified']))
check('unavailable and hard-bound target Apps are blocked', all(x in gate for x in ['targetAppAvailable', 'targetIsHardBoundApp']))
check('explicit user confirmation is mandatory', 'if !evidence.userConfirmed' in gate)
check('unit tests cover fail-closed and individual blockers', all(x in tests for x in ['testProductionMutationRemainsClosed', 'testMissingDeviceValidatedStrategyBlocksEnableAndDisable', 'testHelperIdentityRecoveryAndAuditAreIndependentBarriers', 'testOwnershipPairAvailabilityAndHardBoundRulesBlockMutation', 'testExplicitConfirmationIsRequired']))
check('Helper deployment execution remains closed', 'static let executionReleased = false' in dispatcher and 'static let executionReleased = false' in coordinator and 'static let executionReleased = false' in backend)
check('Helper association commit remains closed', 'static let pluginAssociationCommitReleased = false' in dispatcher and 'static let pluginAssociationCommitReleased = false' in coordinator)
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(v for _, v in checks)}/{len(checks)} passed')
raise SystemExit(0 if all(v for _, v in checks) else 1)
