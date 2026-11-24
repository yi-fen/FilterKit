import XCTest
@testable import FilterKit

final class HelperRequestDispatcherTests: XCTestCase {
    private final class MemoryAudit: HelperAuditSink {
        private(set) var records: [HelperAuditRecord] = []
        var shouldFail = false
        func append(_ record: HelperAuditRecord) throws {
            if shouldFail { throw NSError(domain: "audit", code: 1) }
            records.append(record)
        }
    }

    private func fixture() -> (HelperDeploymentManifest, HelperAuthenticatedPeerContext) {
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 123)
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
            sessionNonce: String(repeating: "b", count: 32), authenticatedAt: Date())
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "test",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/helper.sock")
        return (manifest, context)
    }

    func testHealthRequestRequiresSessionNonceAndAudits() throws {
        let (manifest, context) = fixture()
        let audit = MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let request = HelperIPCEnvelope(messageType: .healthRequest, nonce: context.sessionNonce)
        let response = dispatcher.dispatch(request, context: context)
        XCTAssertEqual(response.messageType, .healthResponse)
        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(audit.records.last?.reasonCode, "health_check")

        let wrongNonce = HelperIPCEnvelope(messageType: .healthRequest, nonce: "wrong")
        let rejected = dispatcher.dispatch(wrongNonce, context: context)
        XCTAssertEqual(rejected.messageType, .rejected)
    }

    func testHealthReturnsStructuredRecoveryStatus() throws {
        let (manifest, context) = fixture()
        let audit = MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let request = HelperIPCEnvelope(messageType: .healthRequest, nonce: context.sessionNonce)
        let response = dispatcher.dispatch(request, context: context)
        XCTAssertEqual(response.messageType, .healthResponse)
        let payload = try XCTUnwrap(response.payload)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(HelperStatusResponse.self, from: payload)
        XCTAssertTrue(status.helperReachable)
        XCTAssertEqual(status.recoveryStatus, .unavailable)
        XCTAssertEqual(status.protocolVersion, HelperIPCEnvelope.currentVersion)
    }

    func testAuthenticatedMaintenanceInspectionAndRecoveryRemainFailClosed() throws {
        let (manifest, context) = fixture()
        let audit = MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let now = Date()
        let inspectBody = HelperMaintenanceRecoveryRequest(action: .inspect, requestNonce: UUID(), requestedAt: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let inspectEnvelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest,
            createdAt: now, nonce: context.sessionNonce, payload: try encoder.encode(inspectBody))
        let inspectResponse = dispatcher.dispatch(inspectEnvelope, context: context, now: now)
        XCTAssertEqual(inspectResponse.messageType, .maintenanceRecoveryResponse)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let inspectResult = try decoder.decode(HelperMaintenanceRecoveryResponse.self,
            from: try XCTUnwrap(inspectResponse.payload))
        XCTAssertEqual(inspectResult.result, .inspected)

        let recoveryTime = Date()
        let recoveryBody = HelperMaintenanceRecoveryRequest(action: .reconcileThreeFileTransaction,
            requestNonce: UUID(), requestedAt: recoveryTime)
        let recoveryEnvelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest,
            createdAt: recoveryTime, nonce: context.sessionNonce, payload: try encoder.encode(recoveryBody))
        let recoveryResponse = dispatcher.dispatch(recoveryEnvelope, context: context, now: recoveryTime)
        XCTAssertEqual(recoveryResponse.messageType, .maintenanceRecoveryResponse)
        let recoveryResult = try decoder.decode(HelperMaintenanceRecoveryResponse.self,
            from: try XCTUnwrap(recoveryResponse.payload))
        XCTAssertEqual(recoveryResult.result, .recoveryNotReleased)
        XCTAssertFalse(HelperRequestDispatcher.executionReleased)
    }

    func testOperationIsStructurallyValidatedButReleaseGateRemainsClosed() throws {
        let (manifest, context) = fixture()
        let audit = MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let operation = HelperOperationRequest(requestID: UUID(), operation: .installDylib,
            pluginID: UUID(), stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
            expectedSHA256: String(repeating: "c", count: 64), createdAt: Date())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let now = Date()
        let envelope = HelperIPCEnvelope(messageType: .operationRequest, requestID: operation.requestID,
            createdAt: now, nonce: context.sessionNonce, payload: try encoder.encode(operation))
        let response = dispatcher.dispatch(envelope, context: context, now: now)
        XCTAssertEqual(response.messageType, .rejected)
        let rejection = try XCTUnwrap(response.payload)
        let decoded = try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: rejection)
        XCTAssertEqual(decoded.code, .executionDisabled)
        XCTAssertEqual(audit.records.last?.reasonCode, "execution_disabled")
        XCTAssertFalse(HelperRequestDispatcher.executionReleased)
    }

    func testReplayAndMalformedPayloadAreRejected() throws {
        let (manifest, context) = fixture()
        let audit = MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let requestID = UUID()
        let operation = HelperOperationRequest(requestID: requestID, operation: .installDylib,
            pluginID: UUID(), stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
            expectedSHA256: String(repeating: "d", count: 64), createdAt: Date())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let now = Date()
        let envelope = HelperIPCEnvelope(messageType: .operationRequest, requestID: requestID,
            createdAt: now, nonce: context.sessionNonce, payload: try encoder.encode(operation))
        XCTAssertEqual(dispatcher.dispatch(envelope, context: context, now: now).messageType, .rejected)
        let replay = dispatcher.dispatch(envelope, context: context, now: now)
        let replayPayload = try XCTUnwrap(replay.payload)
        XCTAssertEqual(try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: replayPayload).code, .replayedRequest)

        let malformed = HelperIPCEnvelope(messageType: .operationRequest, nonce: context.sessionNonce,
            payload: Data("{}".utf8))
        let malformedResponse = dispatcher.dispatch(malformed, context: context, now: Date())
        let malformedPayload = try XCTUnwrap(malformedResponse.payload)
        XCTAssertEqual(try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: malformedPayload).code, .malformedOperation)
    }
}
