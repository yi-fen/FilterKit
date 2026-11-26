#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
diag = (root / 'Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift').read_text()
provider = (root / 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
transport = (root / 'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
tests = (root / 'Tests/UnitTests/HelperPeerIdentityBindingTests.swift').read_text()
checks = {
    'diagnostic records PID generation': 'let pidVersion: UInt64?' in diag,
    'diagnostic records audit session ID': 'let auditSessionID: UInt32?' in diag,
    'diagnostic records audit-token evidence boolean': 'hasAuditTokenEvidence' in diag,
    'diagnostic records complete process-generation evidence boolean': 'hasProcessGenerationEvidence' in diag,
    'raw audit-token digest is not a diagnostic field': 'let auditTokenDigest:' not in diag,
    'provider classifies CDHash failures': 'peer_cdhash_read_failed' in provider,
    'provider classifies audit-token failures': 'peer_audit_token_changed' in provider,
    'provider classifies PID-generation failures': 'peer_pid_generation_read_failed' in provider,
    'transport preserves bounded provider diagnostic codes': 'diagnostic.diagnosticCode.prefix(96)' in transport,
    'tests verify evidence diagnostics': 'testAuthenticationDiagnosticExposesEvidenceWithoutTokenDigest' in tests and 'testAuthenticationDiagnosticMarksIncompleteEvidence' in tests,
    'Darwin transport requires complete evidence': 'hasCompleteDarwinProcessGenerationEvidence(identity)' in transport,
    'all production write gates remain false': all(
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
