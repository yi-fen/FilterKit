import XCTest
@testable import FilterKit

final class HelperIPCAndPolicyTests: XCTestCase {
    func testLengthPrefixedEnvelopeRoundTrip() throws {
        let envelope = HelperIPCEnvelope(messageType: .hello, createdAt: Date(timeIntervalSince1970: 1_700_000_000), nonce: "nonce-123")
        let codec = HelperIPCFrameCodec()
        let decoded = try codec.decode(codec.encode(envelope))
        XCTAssertEqual(decoded, envelope)
    }

    func testSoftAssociationReplacementRequestSurvivesIPCFrameRoundTrip() throws {
        let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(),
            action: .replaceSoftAssociations, dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            targetBundleIdentifier: "com.example.host", expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            desiredSoftAssociations: [
                HelperPluginSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: false),
                HelperPluginSoftAssociation(bundleIdentifier: "com.example.beta", isEnabled: true)
            ])
        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .pluginFilterMutationCommitRequest,
            requestID: request.requestID, createdAt: request.createdAt, nonce: "0123456789abcdef0123456789abcdef",
            payload: try payloadEncoder.encode(request))
        let codec = HelperIPCFrameCodec()
        let decodedEnvelope = try codec.decode(codec.encode(envelope))
        XCTAssertEqual(decodedEnvelope.messageType, .pluginFilterMutationCommitRequest)
        XCTAssertEqual(decodedEnvelope.requestID, request.requestID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedRequest = try decoder.decode(HelperPluginFilterMutationRequest.self,
            from: XCTUnwrap(decodedEnvelope.payload))
        XCTAssertEqual(decodedRequest, request)
        XCTAssertEqual(decodedRequest.desiredSoftAssociations?.count, 2)
    }

    func testLegacyPerAppMutationPayloadDecodesWithoutAssociationSet() throws {
        let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(),
            action: .enableForApp, dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            targetBundleIdentifier: "com.example.target", expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var legacyObject = object
        legacyObject.removeValue(forKey: "desiredSoftAssociations")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HelperPluginFilterMutationRequest.self, from: legacyData)
        XCTAssertEqual(decoded.action, .enableForApp)
        XCTAssertNil(decoded.desiredSoftAssociations)
    }

    func testIPCFrameRejectsTrailingBytes() throws {
        let codec = HelperIPCFrameCodec()
        let envelope = HelperIPCEnvelope(messageType: .hello)
        var frame = try codec.encode(envelope)
        frame.append(0)
        XCTAssertThrowsError(try codec.decode(frame))
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

    func testPeerTrustAlsoEnforcesProvisionedGID() throws {
        let pinned = String(repeating: "c", count: 40)
        let policy = HelperPeerTrustPolicy(allowedUIDs: [501], allowedCDHashes: [pinned], allowedGIDs: [501])
        let expected = HelperPeerIdentity(uid: 501, gid: 501, pid: 77, cdHashHex: pinned,
                                          pidVersion: nil, auditSessionID: nil)
        XCTAssertNoThrow(try policy.verify(expected))
        let wrongGroup = HelperPeerIdentity(uid: 501, gid: 20, pid: 77, cdHashHex: pinned,
                                            pidVersion: nil, auditSessionID: nil)
        XCTAssertThrowsError(try policy.verify(wrongGroup))
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


extension HelperIPCAndPolicyTests {
    func testServerTransportAllowsHealthAndPluginMutationRequests() {
        XCTAssertTrue(HelperIPCServerRequestPolicy.allows(.healthRequest))
        XCTAssertTrue(HelperIPCServerRequestPolicy.allows(.pluginFilterMutationPrepareRequest))
        XCTAssertTrue(HelperIPCServerRequestPolicy.allows(.pluginFilterMutationCommitRequest))
        XCTAssertTrue(HelperIPCServerRequestPolicy.allows(.maintenanceRecoveryRequest))
        XCTAssertTrue(HelperIPCServerRequestPolicy.allows(.operationRequest))
        XCTAssertTrue(HelperIPCServerRequestPolicy.allows(.deploymentBatchRequest))
    }

    func testServerTransportRejectsHandshakeAndResponseOnlyMessagesAsRequests() {
        XCTAssertFalse(HelperIPCServerRequestPolicy.allows(.hello))
        XCTAssertFalse(HelperIPCServerRequestPolicy.allows(.helloAck))
        XCTAssertFalse(HelperIPCServerRequestPolicy.allows(.healthResponse))
        XCTAssertFalse(HelperIPCServerRequestPolicy.allows(.pluginFilterMutationPrepared))
        XCTAssertFalse(HelperIPCServerRequestPolicy.allows(.pluginFilterMutationCommitted))
        XCTAssertFalse(HelperIPCServerRequestPolicy.allows(.rejected))
    }
}

extension HelperIPCAndPolicyTests {
    func testSocketRuntimePolicyRequiresRootOwnedNonWritableParent() {
        XCTAssertTrue(HelperSocketRuntimePolicy.isSafeParent(ownerUID: 0, mode: 0o711))
        XCTAssertFalse(HelperSocketRuntimePolicy.isSafeParent(ownerUID: 501, mode: 0o711))
        XCTAssertFalse(HelperSocketRuntimePolicy.isSafeParent(ownerUID: 0, mode: 0o777))
        XCTAssertFalse(HelperSocketRuntimePolicy.isSafeParent(ownerUID: 0, mode: 0o600))
    }

    func testSocketRuntimePolicyRequiresExactSocketIdentityAndMode() {
        XCTAssertTrue(HelperSocketRuntimePolicy.isExpectedSocket(ownerUID: 0, groupID: 501,
            mode: 0o660, expectedGroupID: 501, expectedMode: 0o660, isSocket: true))
        XCTAssertFalse(HelperSocketRuntimePolicy.isExpectedSocket(ownerUID: 501, groupID: 501,
            mode: 0o660, expectedGroupID: 501, expectedMode: 0o660, isSocket: true))
        XCTAssertFalse(HelperSocketRuntimePolicy.isExpectedSocket(ownerUID: 0, groupID: 20,
            mode: 0o660, expectedGroupID: 501, expectedMode: 0o660, isSocket: true))
        XCTAssertFalse(HelperSocketRuntimePolicy.isExpectedSocket(ownerUID: 0, groupID: 501,
            mode: 0o666, expectedGroupID: 501, expectedMode: 0o660, isSocket: true))
        XCTAssertFalse(HelperSocketRuntimePolicy.isExpectedSocket(ownerUID: 0, groupID: 501,
            mode: 0o660, expectedGroupID: 501, expectedMode: 0o660, isSocket: false))
    }

    func testPeerAuthenticationDiagnosticsAreBoundedAndDoNotStoreFullCDHash() {
        let hash = String(repeating: "a", count: 40)
        let peer = HelperPeerIdentity(uid: 501, gid: 501, pid: 88, cdHashHex: hash,
                                      pidVersion: nil, auditSessionID: nil)
        let event = HelperPeerAuthenticationDiagnostic(stage: .trustPolicy, outcome: .rejected,
            credentials: nil, identity: peer, reasonCode: String(repeating: "x", count: 200))
        XCTAssertEqual(event.cdHashPrefix, String(repeating: "a", count: 12))
        XCTAssertEqual(event.reasonCode.count, 96)
        XCTAssertEqual(event.peerUID, 501)
        XCTAssertEqual(event.peerGID, 501)
        XCTAssertEqual(event.peerPID, 88)
    }
}

extension HelperIPCAndPolicyTests {
    func testServerRequestFreshnessRejectsStaleAndFutureEnvelopes() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(HelperIPCServerRequestPolicy.isFresh(now, now: now))
        XCTAssertTrue(HelperIPCServerRequestPolicy.isFresh(now.addingTimeInterval(-120), now: now))
        XCTAssertTrue(HelperIPCServerRequestPolicy.isFresh(now.addingTimeInterval(120), now: now))
        XCTAssertFalse(HelperIPCServerRequestPolicy.isFresh(now.addingTimeInterval(-121), now: now))
        XCTAssertFalse(HelperIPCServerRequestPolicy.isFresh(now.addingTimeInterval(121), now: now))
    }

    func testSynchronousReplayGuardIsThreadSafeForDuplicateIDs() {
        let guardValue = HelperRequestReplayGuard(retention: 600, capacity: 1024)
        let requestID = UUID()
        let group = DispatchGroup()
        let lock = NSLock()
        var accepted = 0
        for _ in 0..<256 {
            group.enter()
            DispatchQueue.global().async {
                let result = guardValue.accept(requestID)
                if result { lock.lock(); accepted += 1; lock.unlock() }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(accepted, 1)
    }

    func testReplayGuardAcceptsDistinctIDsAndRejectsReuse() {
        let guardValue = HelperRequestReplayGuard(retention: 600, capacity: 8)
        let first = UUID()
        let second = UUID()
        XCTAssertTrue(guardValue.accept(first))
        XCTAssertTrue(guardValue.accept(second))
        XCTAssertFalse(guardValue.accept(first))
    }
}
