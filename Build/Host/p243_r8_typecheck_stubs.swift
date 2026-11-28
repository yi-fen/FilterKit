import Foundation
struct HelperPolicy {
    static func isAbsoluteCleanPath(_ value: String) -> Bool { value.hasPrefix("/") && !value.contains("..") }
    static func isValidCDHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
    static func isSafeRelativePath(_ value: String) -> Bool { !value.hasPrefix("/") && !value.contains("..") }
}
struct HelperDeploymentManifest {}
struct HelperTrustPinSet {
    static let currentSchemaVersion = 1
    init(schemaVersion: Int, bundleIdentifier: String, allowedClientUIDs: [UInt32], allowedAppCDHashes: [String], allowedHelperCDHashes: [String], generation: UInt64, clientTeamIdentifier: String?) {}
    func makeDisabledManifest(routeIdentifier: String, jbRootPath: String, tweakInjectPath: String, stagingRootPath: String, socketPath: String, stagingOwnerUID: UInt32, socketGroupID: UInt32) throws -> HelperDeploymentManifest { HelperDeploymentManifest() }
}
struct HelperAppTrustConfiguration {
    init(schemaVersion: Int, bundleIdentifier: String, allowedHelperCDHashes: [String], generation: UInt64, allowedHelperUIDs: [UInt32], allowedHelperGIDs: [UInt32]) {}
    func validate() throws {}
}
struct HelperReleaseSigningKey {
    enum Status { case active, retired, revoked }
    let identifier: String
    let publicKeyBase64: String
    let status: Status
    let minimumGeneration: UInt64?
    let maximumGeneration: UInt64?
}
protocol HelperReleaseSignatureChecking { func verify(signature: Data, message: Data, publicKey: Data) -> Bool }
