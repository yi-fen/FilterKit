#!/usr/bin/env python3
from pathlib import Path
import re, sys
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

handshake = (root/'Sources/Core/Models/Helper/HelperHandshake.swift').read_text()
runtime = (root/'Sources/Environment/Helper/Runtime/HelperRuntime.swift').read_text()
trust_factory = (root/'Sources/Core/Models/Helper/HelperTrustProvisioning.swift').read_text()
policy = (root/'Sources/Core/Models/Helper/HelperDeploymentModels.swift').read_text()
darwin = (root/'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
project = (root/'Project.yml').read_text()
check('Trust policy checks UID', 'allowedUIDs.contains(identity.uid)' in handshake)
check('Trust policy checks provisioned GID when configured', 'allowedGIDs.contains(identity.gid)' in handshake)
check('Trust policy rejects invalid PID', 'identity.pid > 0' in handshake)
check('Helper pins App GID from manifest socketGroupID', 'allowedGIDs: [manifest.socketGroupID ?? 0]' in runtime)
check('App pins Helper UID/GID to root from provisioned trust config', 'allowedHelperUIDs: [UInt32]?' in trust_factory and 'allowedHelperGIDs: [UInt32]?' in trust_factory and 'Set(helperUIDs)' in trust_factory and 'Set(helperGIDs)' in trust_factory and 'allowedHelperUIDs: [0], allowedHelperGIDs: [0]' in trust_factory)
check('Deployment policy fails closed on missing/mismatched socket GID', 'let provisionedSocketGID = manifest.socketGroupID' in policy and 'peer.gid == provisionedSocketGID' in policy)
check('Darwin provider uses CS_OPS_CDHASH', 'csOpsCDHash: UInt32 = 5' in darwin)
check('Darwin provider rejects all-zero CDHash', 'bytes.contains(where: { $0 != 0 })' in darwin)
check('Helper commit release gate remains closed', 'pluginAssociationCommitReleased = false' in (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text())
check('Helper general execution release gate remains closed', 'executionReleased = false' in (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text())
check('Darwin provider included in Helper target', 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift' in project)

for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'P2-13 static audit: {sum(ok for _,ok in checks)}/{len(checks)} passed')
sys.exit(0 if all(ok for _,ok in checks) else 1)
