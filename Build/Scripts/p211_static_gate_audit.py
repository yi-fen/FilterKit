#!/usr/bin/env python3
"""Static P2-11 permission-boundary audit; does not perform device operations."""
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

transport = (root/'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
runtime = (root/'Sources/Environment/Helper/Runtime/HelperRuntime.swift').read_text()
plan = (root/'Sources/Environment/Helper/Runtime/HelperLifecyclePlan.swift').read_text()
validator = (root/'Sources/Environment/Helper/Runtime/HelperTrustConfigurationValidator.swift').read_text()
provision = (root/'Build/scripts/p209_provision_helper_trust.py').read_text()
check('server default socket mode is 0660', 'socketMode: mode_t = 0o660' in transport)
check('server assigns root and provisioned group before chmod', transport.index('chown(socketPath, 0, gid_t(socketGroupID))') < transport.index('chmod(socketPath, socketMode)'))
check('runtime passes manifest socket group', 'socketGroupID: manifest.socketGroupID ?? 0' in runtime)
check('private directory is traverse-only 0711', 'modeOctal: "0711"' in plan)
check('socket lifecycle artifact is group-scoped 0660', 'modeOctal: "0660"' in plan and 'root:\\(socketGroupID)' in plan)
check('missing socket group fails closed', 'ValidationError.invalidSocketGroup' in validator and 'socketGroupID != 0' in validator)
check('provisioning requires explicit socket GID', '"--socket-gid", type=int, required=True' in provision)
check('no world-writable socket mode remains in active source', 'socketMode: mode_t = 0o666' not in transport and 'socketMode: 0o666' not in runtime)
flags = [
 root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift',
 root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift',
 root/'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift']
flag_text='\n'.join(p.read_text() for p in flags)
check('commit and execution gates remain closed', bool(re.search(r'(?:executionReleased|pluginAssociationCommitReleased)\s*=\s*false', flag_text)) and not bool(re.search(r'(?:executionReleased|pluginAssociationCommitReleased)\s*=\s*true', flag_text)))
for name, ok in checks: print(('PASS' if ok else 'FAIL')+'  '+name)
print(f'P2-11 static gate audit: {sum(ok for _,ok in checks)}/{len(checks)} passed')
sys.exit(0 if all(ok for _,ok in checks) else 1)
