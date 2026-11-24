import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "P1-27", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main struct P127Smoke {
    static func main() throws {
        let plugin = UUID(), now = Date()
        let operations = [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: plugin,
                stagingRelativePath: "task/Test.dylib", targetFileName: "Test.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: now),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: plugin,
                stagingRelativePath: "task/Test.plist", targetFileName: "Test.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: now)
        ]
        let batch = try HelperDeploymentBatchRequest.make(pluginID: plugin, operations: operations, createdAt: now)
        try batch.validate(now: now)
        try require(batch.operations.count == 2, "paired batch not preserved")
        let tampered = HelperDeploymentBatchRequest(batchID: batch.batchID, pluginID: plugin,
            createdAt: now, operations: operations.map { item in
                HelperOperationRequest(requestID: item.requestID, operation: item.operation, pluginID: plugin,
                    stagingRelativePath: item.stagingRelativePath, targetFileName: item.targetFileName,
                    expectedSHA256: String(repeating: "c", count: 64), createdAt: now)
            }, batchSHA256: batch.batchSHA256)
        do { try tampered.validate(now: now); throw NSError(domain: "P1-27", code: 2) }
        catch HelperDeploymentBatchRequest.BatchError.digestMismatch { }
        print("P1-27 batch protocol smoke: PASS (paired validation, canonical digest, tamper rejection)")
    }
}
