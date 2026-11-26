#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
provider = (root / 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
probe = (root / 'Build/DarwinSDK/FilterKitDarwinSDKProbe.swift').read_text()
script = (root / 'Build/scripts/p218_darwin_sdk_preflight.sh').read_text()
project = (root / 'Project.yml').read_text()
checks = {
    'SDK probe imports Darwin and libproc': 'import Darwin' in probe and 'import libproc' in probe,
    'SDK probe checks proc_bsdinfo layout': 'proc_bsdinfo()' in probe and 'MemoryLayout<proc_bsdinfo>.size' in probe,
    'SDK probe checks proc_pidinfo API': 'proc_pidinfo(pid, PROC_PIDTBSDINFO' in probe,
    'SDK probe checks pid generation field': 'info.pbi_pidversion' in probe,
    'SDK probe checks LOCAL_PEERTOKEN getsockopt': 'getsockopt(fd, 0, 0x003' in probe,
    'preflight uses target SDK swift typecheck': 'xcrun --sdk "$SDK" swiftc -target "$TARGET" -typecheck' in script,
    'preflight can build Helper target': ' -scheme FilterKitHelper ' in script and 'build' in script,
    'Helper target includes Darwin provider': 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift' in project,
    'provider fails closed on process generation read error': 'processGenerationReadFailed' in provider,
    'production execution gates remain false': all(
        'static let '+name+' = false' in (root / path).read_text() for path,name in [
            ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','executionReleased'),
            ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','pluginAssociationCommitReleased'),
            ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','executionReleased'),
            ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','pluginAssociationCommitReleased'),
            ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift','executionReleased')]),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} checks passed')
raise SystemExit(0 if all(checks.values()) else 1)
