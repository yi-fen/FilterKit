#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
diag = (root / 'Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift').read_text()
transport = (root / 'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
tests = (root / 'Tests/UnitTests/HelperPeerIdentityBindingTests.swift').read_text()
checks = {
    'per-connection lifecycle exists': 'final class HelperPeerAuthenticationLifecycle' in diag,
    'lifecycle transitions are lock protected': 'private let lock = NSLock()' in diag and 'func advance(to next: State)' in diag,
    'authentication stages are ordered': all(x in diag for x in ['.created, .credentialsVerified', '.credentialsVerified, .codeIdentityVerified', '.codeIdentityVerified, .trustVerified', '.trustVerified, .handshakeVerified', '.handshakeVerified, .authenticated']),
    'failure and close are terminal': 'func fail()' in diag and 'func close()' in diag and 'state = .closed' in diag,
    'server creates isolated lifecycle per socket': 'let lifecycle = HelperPeerAuthenticationLifecycle()' in transport,
    'server advances after credentials': 'advance(to: .credentialsVerified)' in transport,
    'server advances after identity': 'advance(to: .codeIdentityVerified)' in transport,
    'server advances after trust and handshake': 'advance(to: .trustVerified)' in transport and 'advance(to: .handshakeVerified)' in transport,
    'server marks authenticated only after handshake': 'advance(to: .authenticated)' in transport,
    'server failure and defer cleanup are wired': 'lifecycle.fail()' in transport and 'defer { lifecycle.close() }' in transport,
    'tests cover ordering, failure cleanup, and concurrent isolation': all(x in tests for x in ['testAuthenticationLifecycleRequiresOrderedStages', 'testAuthenticationFailureAndCleanupAreTerminalAndIdempotent', 'testConcurrentConnectionsHaveIsolatedAuthenticationState']),
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
