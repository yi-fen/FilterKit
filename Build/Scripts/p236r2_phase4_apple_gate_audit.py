#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

provider = (root / 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
transport = (root / 'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
probe = (root / 'Build/DarwinSDK/FilterKitDarwinSDKProbe.swift').read_text()
script = (root / 'Build/Host/run-p236r2-phase4-apple-validation.sh').read_text()

action = (root / 'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
coord = (root / 'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text()

check('Darwin peer identity reads LOCAL_PEERTOKEN on the connected socket', 'localPeerToken' in provider and 'readAuditToken(socketFD)' in provider)
check('Darwin peer identity obtains CDHash through csops', 'systemCSOps' in provider and 'csOpsCDHash' in provider)
check('Audit token euid/egid/pid are bound to socket credentials', 'auditTokenCredentialMismatch' in provider and 'token[1] == credentials.uid' in provider and 'token[5]' in provider)
check('Audit token is re-read and compared around CDHash lookup', 'beforeToken == afterToken' in provider)
check('Client uses getpeereid and LOCAL_PEERPID', 'getpeereid(fd' in transport and '0x002' in transport)
check('Server uses Darwin getpeereid and LOCAL_PEERPID with Linux-only SO_PEERCRED fallback', 'private func peerCredentials' in transport and 'getpeereid(fd' in transport and '0x002' in transport and 'SO_PEERCRED' in transport)
check('Darwin SDK probe covers getpeereid, LOCAL_PEERPID and LOCAL_PEERTOKEN', all(x in probe for x in ['getpeereid', '0x002', '0x003']))
check('Darwin SDK probe covers csops call signature', 'filterKitProbeCSOps' in probe and 'CS_OPS_CDHASH' in probe)
check('Apple validation script requires macOS and Xcode tools', 'uname -s' in script and 'xcodebuild' in script and 'xcrun' in script and 'xcodegen' in script)
check('Apple validation script builds iPhoneOS and simulator targets', 'generic/platform=iOS' in script and 'platform=iOS Simulator' in script)
check('Apple validation script runs XCTest', ' -resultBundlePath ' in script and ' test ' in script)
check('App association commit gate remains false', re.search(r'pluginAssociationCommitReleased\s*=\s*false', coord) is not None)
check('Helper association commit gate remains false', re.search(r'pluginAssociationCommitReleased\s*=\s*false', action) is not None)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'P2-36-R2 Phase 4 Apple gate audit: {len(checks)-len(failed)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
