#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = (ROOT / "Project.yml").read_text()
TRANSPORT = (ROOT / "Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift").read_text()
DARWIN = (ROOT / "Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift").read_text()
HANDSHAKE = (ROOT / "Sources/Core/Models/Helper/HelperHandshake.swift").read_text()
COORD = (ROOT / "Sources/Environment/Helper/HelperDeploymentCoordinator.swift").read_text()
DISPATCH = (ROOT / "Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift").read_text()
TESTS = ROOT / "Tests/UnitTests"
checks = []
def check(name, condition): checks.append((name, bool(condition)))

check("iOS deployment target remains iOS 15", 'iOS: "15.0"' in PROJECT)
check("App target includes all required source roots", all(f"- path: {p}" in PROJECT for p in ["App", "Sources/Core", "Sources/Environment", "Sources/Features", "Sources/Localization", "Resources"]))
check("FilterKit scheme includes FilterKitTests", "testTargets:" in PROJECT and "- FilterKitTests" in PROJECT)
check("Helper target includes Unix domain socket transport", "Sources/Environment/Helper/Transport/UnixDomainSocketTransport.swift" in PROJECT)
check("Helper target includes Darwin peer identity provider", "Sources/Environment/Helper/Transport/DarwinPeerIdentityProvider.swift" in PROJECT)
check("client validates peer credentials before trust and handshake", TRANSPORT.index("readPeerCredentials(fd)") < TRANSPORT.index("trustEvaluator.verify(identity)") < TRANSPORT.index("makeHello()"))
check("client binds response to request ID and session nonce", "response.requestID == envelope.requestID" in TRANSPORT and "response.nonce == handshake.nonce" in TRANSPORT)
check("server rechecks credentials and binds authenticated context", "credentialsAreStable(before: peer, after: confirmedPeer)" in TRANSPORT and "HelperAuthenticatedPeerContext" in TRANSPORT)
check("server enforces replay guard and request freshness", "replayGuard.accept(request.requestID)" in TRANSPORT and "HelperIPCServerRequestPolicy.isFresh(request.createdAt)" in TRANSPORT)
check("Darwin identity reads CDHash and LOCAL_PEERTOKEN", "systemCSOps" in DARWIN and "localPeerToken" in DARWIN and "readAuditToken" in DARWIN)
check("Darwin kernel peer evidence remains required", "hasKernelPeerEvidence(identity)" in TRANSPORT)
check("App association commit gate remains false", "static let pluginAssociationCommitReleased = false" in COORD)
check("Helper association commit gate remains false", "static let pluginAssociationCommitReleased = false" in DISPATCH)
check("association transaction and peer policy XCTest files exist", all((TESTS / f).exists() for f in ["PluginAssociationCommitIntegrationTests.swift", "HelperPeerIdentityBindingTests.swift", "HelperPluginFilterConfigurationTransactionTests.swift", "HelperPluginFilterMutationRequestTests.swift", "HelperIPCAndPolicyTests.swift", "HelperRequestDispatcherTests.swift"]))
SOCKET_SMOKE = (ROOT / "Build/Host/P2-36-R2-Phase3-IPC-Integration-Smoke.swift").read_text()
check("live socket host integration smoke is present", (ROOT / "Build/Host/P2-36-R2-Phase3-IPC-Integration-Smoke.swift").exists())
check("live socket smoke invokes the real HelperRequestDispatcher", "dispatcher.dispatch(request, context: context)" in SOCKET_SMOKE)
check("live socket smoke verifies an audit record was appended", "audit.count() == 1" in SOCKET_SMOKE)
check("Apple build/test validation script is present", (ROOT / "Build/Host/run-p236r2-phase3-xcode-validation.sh").exists())

failed = [name for name, ok in checks if not ok]
for name, ok in checks: print(f"{'PASS' if ok else 'FAIL'} {name}")
print(f"P2-36-R2 Phase 3 integration audit: {len(checks)-len(failed)}/{len(checks)} passed")
if failed: sys.exit(1)
