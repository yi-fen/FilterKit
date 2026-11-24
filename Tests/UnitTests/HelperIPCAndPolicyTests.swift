import XCTest
@testable import FilterKit

final class HelperIPCAndPolicyTests: XCTestCase {
    func testLengthPrefixedEnvelopeRoundTrip() throws {
        let envelope = HelperIPCEnvelope(messageType: .hello, createdAt: Date(timeIntervalSince1970: 1_700_000_000), nonce: "nonce-123")
        let codec = HelperIPCFrameCodec()
        let decoded = try codec.decode(codec.encode(envelope))
        XCTAssertEqual(decoded, envelope)
    }

    func testFrameRejectsTruncationAndOversize() throws {
        let codec = HelperIPCFrameCodec()
        XCTAssertThrowsError(try codec.decode(Data([0, 0, 0])))
        var length = UInt32(HelperIPCEnvelope.maximumFrameBytes + 1).bigEndian
        let frame = Data(bytes: &length, count: 4)
        XCTAssertThrowsError(try codec.decode(frame))
    }

    func testSafeManifestDefaultsToExecutionDisabled() {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "dopamine-roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/Library/FilterKit/Staging", socketPath: "/var/run/filterkit.sock",
            appCDHashes: [String](repeating: "a", count: 40), helperCDHashes: [String](repeating: "b", count: 40))
        XCTAssertFalse(manifest.executionEnabled)
    }

    func testPolicyFailsClosedWhenExecutionDisabled() {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "rootless",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/Library/FilterKit/Staging", socketPath: "/var/run/filterkit.sock")
        let request = HelperOperationRequest(requestID: UUID(), operation: .installDylib,
            pluginID: UUID(), stagingRelativePath: "task/plugin.dylib", targetFileName: "plugin.dylib",
            expectedSHA256: String(repeating: "a", count: 64), createdAt: Date())
        let peer = HelperPeerIdentity(uid: 501, gid: 501, pid: 123, cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        XCTAssertThrowsError(try HelperPolicy().authorize(request, peer: peer,
            helperCDHashHex: String(repeating: "b", count: 40), manifest: manifest,
            targetExists: false, sourceIsRegularNonSymlink: true, sourceHashMatches: true)) { error in
            XCTAssertEqual(error as? HelperPolicyError, .executionDisabled)
        }
    }

    func testPolicyRejectsUnsafeLeafAndRelativePath() {
        XCTAssertFalse(HelperPolicy.isSafeLeafName("../evil.dylib"))
        XCTAssertFalse(HelperPolicy.isSafeLeafName("nested/plugin.dylib"))
        XCTAssertFalse(HelperPolicy.isSafeRelativePath("task/../../etc/passwd"))
        XCTAssertTrue(HelperPolicy.isSafeRelativePath("task-uuid/plugin.dylib"))
    }

    func testReceiptRequiresExactChangedPathSet() {
        let request = HelperOperationRequest(requestID: UUID(), operation: .installDylib,
            pluginID: UUID(), stagingRelativePath: "task/plugin.dylib", targetFileName: "plugin.dylib",
            expectedSHA256: String(repeating: "a", count: 64), createdAt: Date())
        let receipt = HelperOperationReceipt(requestID: request.requestID, operation: request.operation,
            succeeded: true, exitCode: 0, changedPaths: ["/unexpected"], output: "ok", completedAt: Date())
        XCTAssertFalse(receipt.validates(against: request, expectedPaths: ["/var/jb/usr/lib/TweakInject/plugin.dylib"]))
    }

    func testHandshakeChallengeAndAckRoundTrip() throws {
        var client = HelperHandshake()
        let hello = try client.makeHello()
        XCTAssertEqual(hello.messageType, .hello)
        XCTAssertEqual(hello.nonce?.count, 32)
        let ack = try HelperHandshake.acceptHello(hello)
        try client.acceptHelloAck(ack)
        XCTAssertEqual(client.state, .authenticated)
    }

    func testHandshakeRejectsNonceMismatch() throws {
        var client = HelperHandshake()
        let hello = try client.makeHello()
        let badAck = HelperIPCEnvelope(messageType: .helloAck, requestID: hello.requestID,
                                       nonce: String(repeating: "0", count: 32))
        XCTAssertThrowsError(try client.acceptHelloAck(badAck))
        XCTAssertEqual(client.state, .failed)
    }

    func testPeerTrustRequiresUIDAndPinnedCDHash() throws {
        let policy = HelperPeerTrustPolicy(allowedUIDs: [501],
                                           allowedCDHashes: [String(repeating: "a", count: 40)])
        let peer = HelperPeerIdentity(uid: 501, gid: 501, pid: 77,
                                      cdHashHex: String(repeating: "a", count: 40),
                                      pidVersion: nil, auditSessionID: nil)
        XCTAssertNoThrow(try policy.verify(peer))
        let wrong = HelperPeerIdentity(uid: 501, gid: 501, pid: 77,
                                       cdHashHex: String(repeating: "b", count: 40),
                                       pidVersion: nil, auditSessionID: nil)
        XCTAssertThrowsError(try policy.verify(wrong))
    }

    func testHelperStartupIdentityMustBePinned() throws {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "test",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/staging", socketPath: "/var/run/filterkit.sock",
            helperCDHashes: [String(repeating: "b", count: 40)])
        XCTAssertNoThrow(try HelperStartupIdentityGate.verify(ownCDHash: String(repeating: "b", count: 40), manifest: manifest))
        XCTAssertThrowsError(try HelperStartupIdentityGate.verify(ownCDHash: String(repeating: "a", count: 40), manifest: manifest))
    }

    func testAuditRecordBoundsUntrustedFields() {
        let record = HelperAuditRecord(outcome: .rejected, reasonCode: String(repeating: "r", count: 200),
                                       changedRelativePaths: Array(repeating: String(repeating: "p", count: 300), count: 12),
                                       output: String(repeating: "o", count: 2000))
        XCTAssertEqual(record.reasonCode.count, 96)
        XCTAssertEqual(record.changedRelativePaths.count, 8)
        XCTAssertEqual(record.changedRelativePaths.first?.count, 160)
        XCTAssertEqual(record.output?.count, 1024)
    }

    func testLifecycleProfileIsBoundedAndPersistent() {
        let profile = HelperLifecycleProfile.conservativePersistent
        XCTAssertTrue(profile.keepAlive)
        XCTAssertEqual(profile.throttleIntervalSeconds, 10)
        XCTAssertEqual(profile.maximumConcurrentConnections, 8)
        XCTAssertEqual(profile.idleConnectionTimeoutSeconds, 5)
        XCTAssertEqual(profile.auditFileModeOctal, "0600")
    }

    func testServerReplayGuardRejectsRequestIDReuse() {
        let guardValue = HelperRequestReplayGuard(retention: 600, capacity: 4)
        let id = UUID()
        XCTAssertTrue(guardValue.accept(id))
        XCTAssertFalse(guardValue.accept(id))
    }

    func testSessionContextCarriesNonceAndPeerIdentity() {
        let peer = HelperPeerIdentity(uid: 501, gid: 501, pid: 99,
                                      cdHashHex: String(repeating: "c", count: 40),
                                      pidVersion: nil, auditSessionID: nil)
        let context = HelperAuthenticatedPeerContext(
            peer: HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 99),
            identity: peer, sessionNonce: String(repeating: "d", count: 32), authenticatedAt: Date())
        XCTAssertEqual(context.identity, peer)
        XCTAssertEqual(context.sessionNonce.count, 32)
    }

    func testReplayGuardRejectsDuplicateRequestID() async {
        let guardActor = HelperReplayGuard()
        let id = UUID()
        let first = await guardActor.accept(id)
        let second = await guardActor.accept(id)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }
}
