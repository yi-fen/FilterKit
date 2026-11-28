#!/usr/bin/env python3
from pathlib import Path
import json, re, sys

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / 'Build/P2-44-R1-WRITE-CAPABILITY-MATRIX.json'
DOC = ROOT / 'Build/P2-44-R1-WRITE-CAPABILITY-MATRIX.md'
data = json.loads(MATRIX.read_text())
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

check('matrix schema and phase', data.get('schemaVersion') == 1 and data.get('phase') == 'P2-44-R1')
check('no release gate opened', data.get('releaseGatesOpened') is False)
check('eight capabilities inventoried', len(data.get('capabilities', [])) == 8)
check('capability IDs unique', len({x['id'] for x in data['capabilities']}) == len(data['capabilities']))
check('all capability states explicit', all(x.get('state') for x in data['capabilities']))
check('all closed gate refs represented', len(data.get('crossCuttingClosedSwitches', [])) == 8)
check('documentation exists', DOC.is_file())

gate_sources = {
 'HelperRequestDispatcher.executionReleased': ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', r'static let executionReleased = false'),
 'HelperRequestDispatcher.pluginAssociationCommitReleased': ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', r'static let pluginAssociationCommitReleased = false'),
 'HelperRequestDispatcher.pluginUninstallExecutionReleased': ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', r'static let pluginUninstallExecutionReleased = false'),
 'HelperDeploymentCoordinator.executionReleased': ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift', r'static let executionReleased = false'),
 'HelperDeploymentCoordinator.pluginAssociationCommitReleased': ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift', r'static let pluginAssociationCommitReleased = false'),
 'HelperDeploymentCoordinator.appPluginActivationCommitReleased': ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift', r'static let appPluginActivationCommitReleased = false'),
 'HelperProductionDeploymentBackend.executionReleased': ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift', r'static let executionReleased = false'),
 'PluginToggleReleaseGate.productionMutationReleased': ('Sources/Environment/Deployment/PluginToggleReleaseGate.swift', r'static let productionMutationReleased = false'),
}
for key, (rel, pattern) in gate_sources.items():
    content = (ROOT / rel).read_text()
    check(f'{key} remains false', re.search(pattern, content) is not None)

for x in data['capabilities']:
    check(f"{x['id']} has release phase", bool(x.get('releasePhase')))

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'RESULT {len(checks)-len(failed)}/{len(checks)}')
if failed:
    print('FAILED:', ', '.join(failed), file=sys.stderr)
    sys.exit(1)
