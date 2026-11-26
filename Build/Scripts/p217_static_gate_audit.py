#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
provider = (root / 'Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift').read_text()
policy = (root / 'Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift').read_text()
transport = (root / 'Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift').read_text()
tests = (root / 'Tests/UnitTests/HelperPeerIdentityBindingTests.swift').read_text()
checks = {
    'proc_pidinfo BSD info source': 'proc_pidinfo' in provider and 'PROC_PIDTBSDINFO' in provider,
    'pbi_pidversion consumed': 'pbi_pidversion' in provider,
    'exact structure size enforced': 'guard result == expected' in provider,
    'generation read brackets csops': provider.index('pidVersionBefore = try readPIDVersion') < provider.index('Self.systemCSOps') < provider.index('pidVersionAfter = try readPIDVersion'),
    'generation snapshots compared': 'isStable(before: pidVersionBefore, after: pidVersionAfter)' in provider,
    'audit token snapshots compared': 'beforeToken == afterToken' in provider,
    'Darwin complete evidence requires generation': 'hasKernelAuditTokenEvidence(identity) && identity.pid > 0' in policy and 'identity.pidVersion.map { $0 > 0 } == true' in policy,
    'client and server use complete evidence': transport.count('hasCompleteDarwinProcessGenerationEvidence(identity)') >= 2,
    'generation policy rejects nil and zero': 'guard let before, let after, before > 0, after > 0' in policy,
    'generation unit tests present': 'testPIDGenerationMustBePresentAndStable' in tests and 'testDarwinEvidenceRequiresBothAuditTokenAndPIDGeneration' in tests and 'testConcurrentPIDGenerationPolicyStress' in tests,
    'write gates remain disabled': all('static let '+name+' = false' in (root / path).read_text() for path,name in [
        ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','executionReleased'),
        ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','pluginAssociationCommitReleased'),
        ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','executionReleased'),
        ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','pluginAssociationCommitReleased'),
        ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift','executionReleased')]),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} checks passed')
raise SystemExit(0 if all(checks.values()) else 1)
