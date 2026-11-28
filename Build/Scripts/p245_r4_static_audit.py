#!/usr/bin/env python3
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

collector = (root/'Build/scripts/p245_r4_device_evidence_collector.sh').read_text()
project = (root/'Project.yml').read_text()
files = {
 'dispatcher': (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text(),
 'deployment_coordinator': (root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text(),
 'backend': (root/'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift').read_text(),
 'provisioning': (root/'Sources/Core/Models/Helper/HelperInstallerProvisioning.swift').read_text(),
}
check('collector Darwin-only guard', 'uname -s' in collector and 'Darwin' in collector)
check('collector requires root', 'id -u' in collector and 'run from an explicitly authorized root shell' in collector)
check('collector requires explicit JBROOT', 'FILTERKIT_JBROOT' in collector)
check('collector rejects report inside JBROOT', 'report path must be outside JBROOT' in collector)
check('collector declares no JBROOT mutation', 'NO_JBROOT_MUTATION' in collector)
check('collector does not run activation commands', not re.search(r'\b(rename|mv|rm|launchctl\s+(kickstart|bootstrap|bootout))\b', collector))
check('Helper signing remains disabled', 'CODE_SIGNING_ALLOWED: NO' in project)
check('dispatcher execution gate closed', 'static let executionReleased = false' in files['dispatcher'])
check('deployment coordinator gate closed', 'static let executionReleased = false' in files['deployment_coordinator'])
check('production backend gate closed', 'static let executionReleased = false' in files['backend'])
check('provisioning default execution disabled', 'executionEnabled: false' in files['provisioning'])
check('activation commit defaults disabled', 'activationCommitExecutionEnabled: Bool = false' in files['dispatcher'])
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'} {name}")
print(f"R4 static audit: {sum(ok for _,ok in checks)}/{len(checks)}")
sys.exit(0 if all(ok for _,ok in checks) else 1)
