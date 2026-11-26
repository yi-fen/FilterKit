#!/usr/bin/env python3
"""P2-07 release-gate and source-surface audit; read-only, no device/file mutation."""
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(name, ok, detail):
    checks.append((name, bool(ok), detail))

dispatcher = (ROOT/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
coordinator = (ROOT/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text()
backend = (ROOT/'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift').read_text()
check('Helper commit release gate closed', bool(re.search(r'static let pluginAssociationCommitReleased = false', dispatcher)), 'Dispatcher gate must remain false')
check('App commit release gate closed', bool(re.search(r'static let pluginAssociationCommitReleased = false', coordinator)), 'Coordinator gate must remain false')
check('General deployment gate closed', bool(re.search(r'static let executionReleased = false', dispatcher)) and bool(re.search(r'static let executionReleased = false', coordinator)) and bool(re.search(r'static let executionReleased = false', backend)), 'All three deployment execution gates must remain false')
check('Commit request re-authorizes', 'authorizer.prepare(request, now: now)' in dispatcher, 'Commit branch must re-run Helper authorizer')
check('Commit transaction call present', 'transaction.execute(prepared)' in dispatcher, 'Commit branch must invoke dedicated transaction')
check('Pre-commit audit barrier present', 'plugin_association_commit_authorized' in dispatcher, 'Durable audit acceptance precedes transaction')
models = (ROOT/'Sources/Core/Models/Helper/HelperPluginFilterMutationModels.swift').read_text()
check('Request model does not expose absolute path field', not re.search(r'let\s+\w*(?:absolute)?Path\s*:', models), 'IPC mutation request must remain leaf-name/intent based')
transaction = (ROOT/'Sources/Environment/Helper/Execution/HelperPluginFilterConfigurationTransaction.swift').read_text()
check('Dedicated two-file transaction present', 'Filter.plist' in transaction or 'plist' in transaction.lower(), 'Transaction source exists and references plist configuration')
check('Dylib is not a write/rename destination', not re.search(r'(?:write|copy|rename)\([^\n]*dylibFileName', transaction), 'Dylib identity may be checked, but transaction write/rename calls must not target it')
for name, ok, detail in checks:
    print(f"{'PASS' if ok else 'FAIL'} | {name} | {detail}")
print(f"\n{sum(ok for _,ok,_ in checks)}/{len(checks)} checks passed")
sys.exit(0 if all(ok for _,ok,_ in checks) else 1)
