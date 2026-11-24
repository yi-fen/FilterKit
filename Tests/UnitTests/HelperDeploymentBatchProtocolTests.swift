import XCTest
@testable import FilterKit

final class HelperDeploymentBatchProtocolTests: XCTestCase {
    private func pair(pluginID: UUID = UUID(), date: Date = Date()) -> [HelperOperationRequest] {
        [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: date),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Demo.plist", targetFileName: "Demo.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: date)
        ]
    }

    private final class Audit: HelperAuditSink {
        var records: [HelperAuditRecord] = []
        func append(_ record: HelperAuditRecord) throws { records.append(record) }
    }

    func testBatchDigestAndShapeValidation() throws {
        let date = Date()
        let operations = pair(date: date)
        let batch = try HelperDeploymentBatchRequest.make(pluginID: operations[0].pluginID,
                                                          operations: operations, createdAt: date)
        XCTAssertNoThrow(try batch.validate(now: date))

        var tampered = batch
        let altered = operations.map { item in
            HelperOperationRequest(requestID: item.requestID, operation: item.operation,
                pluginID: item.pluginID, stagingRelativePath: item.stagingRelativePath,
                targetFileName: item.targetFileName, expectedSHA256: String(repeating: "c", count: 64),
                createdAt: item.createdAt)
        }
        tampered = HelperDeploymentBatchRequest(batchID: batch.batchID, pluginID: batch.pluginID,
            createdAt: batch.createdAt, operations: altered, batchSHA256: batch.batchSHA256)
        XCTAssertThrowsError(try tampered.validate(now: date))
        XCTAssertThrowsError(try HelperDeploymentBatchRequest.make(pluginID: operations[0].pluginID,
            operations: Array(operations.prefix(1)), createdAt: date).validate(now: date))
    }

    func testDispatcherValidatesWholeBatchThenKeepsExecutionClosed() throws {
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 123)
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        let nonce = String(repeating: "b", count: 32)
        let now = Date()
        let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
            sessionNonce: nonce, authenticatedAt: now)
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "test",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/helper.sock")
        let audit = Audit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let operations = pair(date: now)
        let batch = try HelperDeploymentBatchRequest.make(pluginID: operations[0].pluginID,
                                                          operations: operations, createdAt: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .deploymentBatchRequest, requestID: batch.batchID,
            createdAt: now, nonce: nonce, payload: try encoder.encode(batch))
        let response = dispatcher.dispatch(envelope, context: context, now: now)
        XCTAssertEqual(response.messageType, .rejected)
        let rejection = try XCTUnwrap(response.payload)
        XCTAssertEqual(try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: rejection).code,
                       .executionDisabled)
        XCTAssertEqual(audit.records.last?.reasonCode, "execution_disabled")
        let wrappedReplay = try HelperDeploymentBatchRequest.make(pluginID: operations[0].pluginID,
            operations: operations, createdAt: now)
        let replayEnvelope = HelperIPCEnvelope(messageType: .deploymentBatchRequest,
            requestID: wrappedReplay.batchID, createdAt: now, nonce: nonce, payload: try encoder.encode(wrappedReplay))
        let replayResponse = dispatcher.dispatch(replayEnvelope, context: context, now: now)
        let replayPayload = try XCTUnwrap(replayResponse.payload)
        XCTAssertEqual(try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self,
            from: replayPayload).code, .replayedRequest)
        XCTAssertFalse(HelperRequestDispatcher.executionReleased)
    }

    func testCoordinatorBuildsSingleBatchEnvelope() throws {
        final class NoopTransport: HelperIPCTransport {
            func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope { envelope }
        }
        let date = Date()
        let operations = pair(date: date)
        let coordinator = HelperDeploymentCoordinator(transport: NoopTransport())
        let envelope = try coordinator.makeBatchEnvelope(operations, createdAt: date)
        XCTAssertEqual(envelope.messageType, .deploymentBatchRequest)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HelperDeploymentBatchRequest.self, from: XCTUnwrap(envelope.payload))
        XCTAssertEqual(envelope.requestID, decoded.batchID)
        XCTAssertNoThrow(try decoded.validate(now: date))
    }
}
