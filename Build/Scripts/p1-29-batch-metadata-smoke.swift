import Foundation
@main struct P129BatchMetadataSmoke {
    static func main() throws {
        let now = Date(), pluginID = UUID()
        let operations = [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: now),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Demo.plist", targetFileName: "Demo.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: now)
        ]
        let metadata = HelperDeploymentBatchMetadata(hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [.init(bundleIdentifier: "com.example.soft", isEnabled: true)])
        let batch = try HelperDeploymentBatchRequest.make(pluginID: pluginID, operations: operations,
            deploymentMetadata: metadata, createdAt: now)
        try batch.validate(now: now)
        var altered = batch
        altered.deploymentMetadata = .init(hardBoundBundleIdentifier: "com.example.attacker", softAssociations: [])
        do { try altered.validate(now: now); throw NSError(domain: "P1-29", code: 1) }
        catch HelperDeploymentBatchRequest.BatchError.digestMismatch { }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HelperDeploymentBatchRequest.self, from: encoder.encode(batch))
        try decoded.validate(now: now)
        print("P1-29 batch metadata smoke: PASS (hard-bound/soft association validation, digest binding, Codable round trip)")
    }
}
