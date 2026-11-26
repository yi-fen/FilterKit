#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, ok): checks.append((name, bool(ok)))
files = {
 'toggle gate': ('Sources/Environment/Deployment/PluginToggleReleaseGate.swift', 'static let productionMutationReleased = false'),
 'Helper dispatcher execution': ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', 'static let executionReleased = false'),
 'Helper dispatcher association': ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', 'static let pluginAssociationCommitReleased = false'),
 'deployment coordinator execution': ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift', 'static let executionReleased = false'),
 'deployment coordinator association': ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift', 'static let pluginAssociationCommitReleased = false'),
 'production backend execution': ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift', 'static let executionReleased = false'),
}
for name, (path, token) in files.items(): check(name + ' remains closed', token in (root/path).read_text())
validator = (root/'Build/scripts/p229_device_acceptance.py').read_text()
check('device evidence requires explicit manual capture kind', 'manual-device-capture' in validator)
check('evidence freshness is bounded to 24 hours', '24 * 3600' in validator)
check('actual target injection observation is mandatory', 'checks.target_injection_observed' in validator)
check('disable-after-restart observation is mandatory', 'checks.disable_prevents_injection_after_restart' in validator)
check('validator is explicitly read-only and non-attesting', 'does not authenticate operator claims' in validator)
for name, ok in checks: print(('PASS ' if ok else 'FAIL ') + name)
print(f'{sum(v for _,v in checks)}/{len(checks)} passed')
raise SystemExit(0 if all(v for _,v in checks) else 1)
