#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
transport = (root/'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
policy = (root/'Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift').read_text()
audit = (root/'Sources/Environment/Helper/Runtime/HelperAuditFileSink.swift').read_text()
checks = {
    'server re-reads peer credentials after identity lookup': 'let confirmedPeer = try peerCredentials(fd)' in transport,
    'client re-reads peer credentials after identity lookup': 'let confirmedCredentials = try readPeerCredentials(fd)' in transport,
    'socket credential snapshots must be stable': 'credentialsAreStable(before:' in transport and 'before == after && before.pid > 0' in policy,
    'identity UID/GID/PID must match socket credentials': 'identity(_ identity: HelperPeerIdentity' in policy and 'identity.pid == credentials.pid' in policy,
    'audit file append fsyncs data': 'fsync(fd)' in audit,
    'audit append fsyncs parent directory': 'fsync(directoryFD)' in audit,
    'rotation fsyncs parent directory': 'guard fsync(directoryFD) == 0 else { throw SinkError.syncFailed(errno) }' in audit,
    'audit sink retains no-follow open': 'O_NOFOLLOW' in audit,
    'commit release gate remains closed': 'pluginAssociationCommitReleased = false' in (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text(),
    'general execution release gate remains closed': 'executionReleased = false' in (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text(),
}
failed=[]
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + name)
    if not ok: failed.append(name)
print(f'P2-15 static audit: {len(checks)-len(failed)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
