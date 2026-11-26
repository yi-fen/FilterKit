#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
provider = (root/'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
transport = (root/'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
models = (root/'Sources/Core/Models/Helper/HelperIPCModels.swift').read_text()
policy = (root/'Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift').read_text()
dispatcher = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
checks = {
    'Darwin provider requests LOCAL_PEERTOKEN': 'localPeerToken: Int32 = 0x003' in provider,
    'audit token length is bounded to eight words': 'auditTokenWordCount = 8' in provider,
    'audit token euid/egid/PID match socket credentials': 'token[1] == credentials.uid' in provider and 'token[2] == credentials.gid' in provider and 'token[5]) == credentials.pid' in provider,
    'token is re-read after csops': 'let afterToken' in provider and 'beforeToken == afterToken' in provider,
    'raw token is represented by digest': 'auditTokenDigest: tokenData.map(SHA256Digest.hex)' in provider,
    'identity model carries optional token digest': 'let auditTokenDigest: String?' in models,
    'Darwin transport requires complete token plus PID-generation evidence': transport.count('Self.auditTokenEvidenceIsSufficient(identity)') >= 2 and 'hasCompleteDarwinProcessGenerationEvidence(identity)' in transport,
    'token digest format is strictly checked': '^[0-9a-fA-F]{64}$' in policy,
    'PID version is kernel-read and bound around csops': 'proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO' in provider and 'pidVersion: pidVersionBefore' in provider and 'isStable(before: pidVersionBefore, after: pidVersionAfter)' in provider,
    'plugin commit gate remains closed': 'pluginAssociationCommitReleased = false' in dispatcher,
    'general execution gate remains closed': 'executionReleased = false' in dispatcher,
}
failed=[]
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + name)
    if not ok: failed.append(name)
print(f'P2-16 compatibility audit (updated for P2-17+): {len(checks)-len(failed)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
