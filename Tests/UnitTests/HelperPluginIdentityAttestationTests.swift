import XCTest
@testable import FilterKit

final class HelperPluginIdentityAttestationTests: XCTestCase {
    func testRequestAcceptsOnlyLeafNamesAndMatchingPluginPair() {
        let now = Date()
        let valid = HelperPluginIdentityAttestationRequest(requestID: UUID(),
            pluginID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist", createdAt: now)
        XCTAssertTrue(valid.validate(now: now))

        let traversal = HelperPluginIdentityAttestationRequest(requestID: UUID(), pluginID: valid.pluginID,
            dylibFileName: "../Example.dylib", plistFileName: "Example.plist", createdAt: now)
        XCTAssertFalse(traversal.validate(now: now))

        let mismatchedPair = HelperPluginIdentityAttestationRequest(requestID: UUID(), pluginID: valid.pluginID,
            dylibFileName: "Other.dylib", plistFileName: "Example.plist", createdAt: now)
        XCTAssertFalse(mismatchedPair.validate(now: now))
    }

    func testUnverifiedOrRejectedAttestationNeverPermitsActivation() {
        let base = HelperPluginIdentityAttestation(requestID: UUID(), status: .unavailable,
            reasonCode: "helper_unavailable", pluginID: nil, dylibFileName: nil, plistFileName: nil,
            dylibSHA256: nil, plistSHA256: nil, manifestSHA256: nil, machOIdentitySHA256: nil,
            hardBoundBundleIdentifier: nil, softAssociations: nil, filterConfiguration: nil,
            completedAt: Date())
        XCTAssertFalse(base.isVerified)

        let rejected = HelperPluginIdentityAttestation(requestID: UUID(), status: .rejected,
            reasonCode: "package_manager_owned", pluginID: nil, dylibFileName: nil, plistFileName: nil,
            dylibSHA256: nil, plistSHA256: nil, manifestSHA256: nil, machOIdentitySHA256: nil,
            hardBoundBundleIdentifier: nil, softAssociations: nil, filterConfiguration: nil,
            completedAt: Date())
        XCTAssertFalse(rejected.isVerified)
    }

    func testCoordinatorUsesReadOnlyIdentityMessageAndBindsResponseID() async throws {
        let pluginID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let filter = PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
            bundles: ["com.example.app"], executables: [], classes: [], modeDescription: nil,
            unknownKeys: [], warnings: [])
        let attestation = HelperPluginIdentityAttestation(requestID: UUID(), status: .verified,
            reasonCode: "helper_verified", pluginID: pluginID, dylibFileName: "Example.dylib",
            plistFileName: "Example.plist", dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64), manifestSHA256: String(repeating: "c", count: 64),
            machOIdentitySHA256: String(repeating: "d", count: 64),
            hardBoundBundleIdentifier: "com.example.app", softAssociations: [],
            filterConfiguration: filter, completedAt: Date())
        let transport = IdentityAttestationTransport(attestation: attestation)
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        _ = try await coordinator.attestPluginIdentity(pluginID: pluginID,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist")
        XCTAssertEqual(transport.lastMessageType, .pluginIdentityAttestationRequest)
        XCTAssertEqual(transport.lastResponseMessageType, .pluginIdentityAttestationResponse)
        XCTAssertFalse(HelperDeploymentCoordinator.pluginAssociationCommitReleased)
    }
}

private final class IdentityAttestationTransport: HelperIPCTransport {
    let attestation: HelperPluginIdentityAttestation
    private(set) var lastMessageType: HelperIPCMessageType?
    private(set) var lastResponseMessageType: HelperIPCMessageType?

    init(attestation: HelperPluginIdentityAttestation) { self.attestation = attestation }

    func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope {
        lastMessageType = envelope.messageType
        var response = attestation
        response = HelperPluginIdentityAttestation(requestID: envelope.requestID, status: attestation.status,
            reasonCode: attestation.reasonCode, pluginID: attestation.pluginID,
            dylibFileName: attestation.dylibFileName, plistFileName: attestation.plistFileName,
            dylibSHA256: attestation.dylibSHA256, plistSHA256: attestation.plistSHA256,
            manifestSHA256: attestation.manifestSHA256, machOIdentitySHA256: attestation.machOIdentitySHA256,
            hardBoundBundleIdentifier: attestation.hardBoundBundleIdentifier,
            softAssociations: attestation.softAssociations, filterConfiguration: attestation.filterConfiguration,
            completedAt: Date())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        lastResponseMessageType = .pluginIdentityAttestationResponse
        return HelperIPCEnvelope(messageType: .pluginIdentityAttestationResponse,
            requestID: envelope.requestID, createdAt: Date(), payload: try encoder.encode(response))
    }
}
