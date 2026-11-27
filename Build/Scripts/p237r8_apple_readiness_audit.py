#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[2]
def read(p): return (ROOT / p).read_text()
project = read('Project.yml')
provider = read('Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift')
probe = read('Build/DarwinSDK/FilterKitDarwinSDKProbe.swift')
runner = read('Build/Host/run-p237r8-apple-validation.sh')
sign = read('Build/Host/verify-p237r8-signed-artifacts.sh')
coord = read('Sources/Environment/Helper/HelperDeploymentCoordinator.swift')
dispatcher = read('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift')
app_coord = read('Sources/Environment/Helper/HelperDeploymentCoordinator.swift')
checks = [
 ('Project declares iOS 15 deployment target', 'iOS: "15.0"' in project),
 ('Swift language mode remains Swift 5', 'SWIFT_VERSION: 5.0' in project),
 ('App target includes App and Sources groups', 'path: App' in project and 'path: Sources/Environment' in project),
 ('Helper target includes HelperRuntime and Darwin transport', 'path: HelperRuntime' in project and 'DarwinPeerIdentityProvider.swift' in project),
 ('Unit test target is attached to FilterKit scheme', 'testTargets:' in project and '- FilterKitTests' in project),
 ('Darwin provider reads LOCAL_PEERTOKEN from accepted socket', 'readAuditToken(socketFD)' in provider and 'localPeerToken: Int32 = 0x003' in provider),
 ('Darwin provider brackets csops with stable audit token', 'beforeToken == afterToken' in provider and 'systemCSOps' in provider),
 ('Darwin compile probe covers public socket APIs and csops', all(x in probe for x in ['getpeereid', '0x002', '0x003', 'filterKitProbeCSOps'])),
 ('Apple runner blocks non-macOS execution', 'uname -s' in runner and 'Darwin' in runner and 'BLOCKED' in runner),
 ('Apple runner generates project outside source root', '--project "$ART/FilterKit.xcodeproj"' in runner),
 ('Apple runner compiles simulator and iPhoneOS targets', 'iphonesimulator' in runner and 'generic/platform=iOS' in runner),
 ('Apple runner executes XCTest with result bundle', ' -resultBundlePath ' in runner and ' test ' in runner),
 ('Signed artifact inspector verifies signatures', 'codesign --verify --strict' in sign),
 ('Signed artifact inspector pins expected TeamIdentifier', 'FILTERKIT_EXPECTED_TEAM_ID' in sign and 'TeamIdentifier=' in sign),
 ('Signed artifact inspector captures CDHash and entitlements', "CDHash=" in sign and 'codesign -d --entitlements :-' in sign),
 ('App activation production Gate remains closed', 'appPluginActivationCommitReleased = false' in app_coord),
 ('Helper activation execution default remains disabled', re.search(r'activationCommitExecutionEnabled: Bool = false', dispatcher) is not None),
]
failed=[]
for name, ok in checks:
 print(('PASS ' if ok else 'FAIL ') + name)
 if not ok: failed.append(name)
print(f'P2-37-R8 Apple readiness audit: {len(checks)-len(failed)}/{len(checks)} passed')
if failed: sys.exit(1)
