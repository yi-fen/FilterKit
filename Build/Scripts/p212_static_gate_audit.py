#!/usr/bin/env python3
"""P2-12 transport/request-path static audit; does not perform device operations."""
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
handshake = (root/'Sources/Core/Models/Helper/HelperHandshake.swift').read_text()
transport = (root/'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
dispatcher = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
coordinator = (root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text()
checks=[]
def check(name, ok): checks.append((name, bool(ok)))
policy = handshake.split('enum HelperIPCServerRequestPolicy',1)[1] if 'enum HelperIPCServerRequestPolicy' in handshake else ''
for token in ['.healthRequest','.maintenanceRecoveryRequest','.operationRequest','.deploymentBatchRequest','.pluginFilterMutationPrepareRequest','.pluginFilterMutationCommitRequest']:
    check(f'server policy includes {token}', token in policy)
check('server applies centralized request policy', 'HelperIPCServerRequestPolicy.allows(request.messageType)' in transport)
check('server binds request to handshake nonce', 'request.nonce == nonce' in transport)
check('server rejects stale request timestamps through centralized freshness policy', 'HelperIPCServerRequestPolicy.isFresh(request.createdAt)' in transport and 'static func isFresh' in handshake)
check('Darwin peer identity uses csops CDHash', 'systemCSOps' in (root/'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text())
check('dispatcher has Prepare and Commit cases', 'case .pluginFilterMutationPrepareRequest:' in dispatcher and 'case .pluginFilterMutationCommitRequest:' in dispatcher)
check('App coordinator validates health response', 'response.messageType == .healthResponse' in coordinator and 'status.helperReachable' in coordinator)
for file in [root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift', root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift', root/'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift']:
    t=file.read_text()
    check(f'{file.name} execution/commit gates remain closed', bool(re.search(r'(?:executionReleased|pluginAssociationCommitReleased)\s*=\s*false',t)) and not bool(re.search(r'(?:executionReleased|pluginAssociationCommitReleased)\s*=\s*true',t)))
for name, ok in checks: print(('PASS' if ok else 'FAIL')+'  '+name)
print(f'P2-12 static gate audit: {sum(x for _,x in checks)}/{len(checks)} passed')
sys.exit(0 if all(x for _,x in checks) else 1)
