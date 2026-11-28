#!/usr/bin/env python3
"""P2-45-R2 static qualification of Helper peer identity and AF_UNIX IPC trust boundaries."""
from pathlib import Path
import re, sys
ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(name, ok):
    checks.append((name, bool(ok)))
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

def read(rel):
    return (ROOT / rel).read_text()

provider = read('Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift')
transport = read('Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift')
peer_policy = read('Sources/Environment/Helper/Transport/HelperPeerAuthenticationDiagnostics.swift')
handshake = read('Sources/Core/Models/Helper/HelperHandshake.swift')
models = read('Sources/Core/Models/Helper/HelperIPCModels.swift')
runtime = read('Sources/Environment/Helper/Runtime/HelperRuntime.swift')
validator = read('Sources/Environment/Helper/Runtime/HelperTrustConfigurationValidator.swift')

check('Darwin peer adapter is compile-time guarded by canImport(Darwin)', '#if canImport(Darwin)' in provider)
check('CDHash is obtained from kernel csops rather than IPC payload', 'Self.systemCSOps(pid, Self.csOpsCDHash' in provider)
check('LOCAL_PEERTOKEN is read from the connected socket', 'getsockopt(fd, 0, Self.localPeerToken' in provider)
check('audit token is sampled both before and after CDHash lookup', 'beforeToken' in provider and 'afterToken' in provider and 'beforeToken == afterToken' in provider)
check('audit token credentials are cross-checked against socket credentials', 'validate(token: token, credentials: credentials)' in provider)
check('code signing identity is derived from SecTaskCreateWithAuditToken', 'SecTaskCreateWithAuditToken' in provider)
check('Team ID is read from signed entitlement and format-validated', 'com.apple.developer.team-identifier' in provider and '^[A-Z0-9]{10}$' in provider)
check('identity failure is closed when signed identity cannot be read', 'guard let signedIdentity else { throw IdentityError.codeSigningIdentityUnavailable }' in provider)
check('self CDHash lookup uses ownCDHash without requiring peer token', 'func ownCDHash() throws' in provider and 'readCDHash(pid: getpid())' in provider)
check('client re-reads socket credentials after identity lookup', transport.count('readPeerCredentials(fd)') >= 2)
check('client compares identity UID/GID/PID with kernel socket credentials', 'identity(identity, matches: credentials)' in transport)
check('client requires Darwin kernel peer-token evidence', 'Self.auditTokenEvidenceIsSufficient(identity)' in transport)
check('server re-reads socket credentials after identity lookup', transport.count('peerCredentials(fd)') >= 2)
server = transport.split('private func serve(_ fd: Int32)', 1)[1]
check('server authenticates identity before trust policy', server.index('identityProvider.identity(for: peer, socketFD: fd)') < server.index('try trustEvaluator.verify(identity)'))
check('server trust verification precedes handshake', transport.index('try trustEvaluator.verify(identity)') < transport.index('hello = try readFrame(fd)'))
check('server request allow-list and nonce freshness are enforced', 'HelperIPCServerRequestPolicy.allows(request.messageType)' in transport and 'request.nonce == nonce' in transport and 'isFresh(request.createdAt)' in transport)
check('server replay guard rejects duplicate request IDs', 'replayGuard.accept(request.requestID)' in transport)
check('socket node is checked with lstat and exact owner/group/mode', 'lstat($0, &info)' in transport and 'isExpectedSocket' in transport)
check('socket parent is opened with O_NOFOLLOW and validated', 'O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC' in transport and 'isSafeParent' in transport)
check('socket mode is not world writable by default', 'socketMode: mode_t = 0o660' in transport)
check('handshake challenge is freshly generated', 'UUID().uuidString.replacingOccurrences' in handshake)
check('handshake binds helloAck to request ID and nonce', 'envelope.requestID == requestID' in handshake and 'envelope.nonce == nonce' in handshake)
check('IPC frames are size bounded', 'maximumFrameBytes = 96 * 1024' in models)
check('IPC response binds request ID, nonce, protocol and timestamp', 'response.requestID == envelope.requestID' in transport and 'response.nonce == handshake.nonce' in transport)
check('Helper startup trust requires client Bundle ID and Team ID', 'missingClientCodeIdentity' in validator and 'allowedClientTeamIdentifier' in validator)
check('Helper runtime validates trust manifest before opening socket', 'HelperTrustConfigurationValidator.validate(manifest)' in runtime and runtime.index('HelperTrustConfigurationValidator.validate(manifest)') < runtime.index('UnixDomainSocketServer('))
check('trust failure diagnostics include code-signing identity failure', 'case .codeSigningIdentityUnavailable: return "peer_code_signing_identity_unavailable"' in transport)
check('all production execution gates remain closed', all('static let executionReleased = false' in read(p) for p in [
 'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift',
 'Sources/Environment/Helper/HelperDeploymentCoordinator.swift',
 'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift']))
check('Helper target remains unsigned pending R1 Apple signing qualification', 'CODE_SIGNING_ALLOWED: NO' in read('Project.yml').split('  FilterKitHelper:',1)[1].split('  FilterKitTests:',1)[0])
check('new identity/IPC regression tests are present', read('Tests/UnitTests/HelperPeerIdentityBindingTests.swift').count('func test') >= 18)

failed = sum(not ok for _, ok in checks)
print(f"P2-45-R2 static audit: {len(checks)-failed}/{len(checks)} passed; {failed} failed")
sys.exit(1 if failed else 0)
