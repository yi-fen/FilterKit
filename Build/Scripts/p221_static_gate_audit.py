#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
transport = (root / 'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
policy = (root / 'Sources/Core/Models/Helper/HelperHandshake.swift').read_text()
diag = (root / 'Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift').read_text()
tests = (root / 'Tests/UnitTests/HelperIPCAndPolicyTests.swift').read_text()
checks = {
    'server owns shared replay guard': 'private let replayGuard: HelperRequestReplayGuard' in transport and 'self.replayGuard = replayGuard' in transport,
    'replay guard checked before request handler': transport.index('replayGuard.accept(request.requestID)') < transport.index('let response = try handler(request, context)'),
    'duplicate request ID is rejected': 'replayedRequest }' in transport and 'duplicate_request_id_rejected' in transport,
    'request type allow-list retained': 'HelperIPCServerRequestPolicy.allows(request.messageType)' in transport,
    'session nonce bound before dispatch': 'request.nonce == nonce' in transport,
    'freshness policy has bounded tolerance': 'static func isFresh(_ createdAt: Date' in policy and 'delta >= -tolerance && delta <= tolerance' in policy,
    'freshness checked before replay cache': transport.index('isFresh(request.createdAt)') < transport.index('replayGuard.accept(request.requestID)'),
    'request validation diagnostics available': 'requestValidation' in diag and '.init(stage: .requestValidation' in transport,
    'frame maximum remains bounded': 'length <= HelperIPCEnvelope.maximumFrameBytes' in transport,
    'fragmented reads loop until complete': 'while offset < count' in transport and 'recv(fd, base.advanced(by: offset)' in transport,
    'server socket timeouts retained': 'timeval(tv_sec: 5, tv_usec: 0)' in transport,
    'connection semaphore retained': 'slots.wait(timeout: .now())' in transport and 'self?.slots.signal()' in transport,
    'tests cover freshness and concurrent replay': all(x in tests for x in ['testServerRequestFreshnessRejectsStaleAndFutureEnvelopes', 'testSynchronousReplayGuardIsThreadSafeForDuplicateIDs', 'testReplayGuardAcceptsDistinctIDsAndRejectsReuse']),
    'all production write gates remain false': all('static let '+name+' = false' in (root / path).read_text() for path,name in [
        ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','executionReleased'),
        ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','pluginAssociationCommitReleased'),
        ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','executionReleased'),
        ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','pluginAssociationCommitReleased'),
        ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift','executionReleased')]),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} checks passed')
raise SystemExit(0 if all(checks.values()) else 1)
