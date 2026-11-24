import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "P1-22", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func writeFile(_ data: Data, _ url: URL, mode: Int16 = 0o600) throws {
    try data.write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path)
}

let fm = FileManager.default
let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-22-\(UUID().uuidString)", isDirectory: true)
let staging = base.appendingPathComponent("staging", isDirectory: true)
let task = staging.appendingPathComponent("task", isDirectory: true)
let target = base.appendingPathComponent("target", isDirectory: true)
try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try fm.createDirectory(at: task, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
defer { try? fm.removeItem(at: base) }
let dylibData = Data([0x4d, 0x5a, 0x90, 0x00, 0x01])
let plistData = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.app"]]], format: .xml, options: 0)
try writeFile(dylibData, task.appendingPathComponent("Demo.dylib"))
try writeFile(plistData, task.appendingPathComponent("Demo.plist"))
let priorPlist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.old.app"]]], format: .xml, options: 0)
try writeFile(priorPlist, target.appendingPathComponent("Demo.plist"), mode: 0o644)
let dylibHash = SHA256Digest.hex(dylibData)
let plistHash = SHA256Digest.hex(plistData)
let manifestBytes = Data("verified-manifest-fixture".utf8)
let proof = try HelperOwnershipProof(pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
    dylibSHA256: dylibHash, plistSHA256: plistHash, manifestSchemaVersion: 3,
    manifestSHA256: SHA256Digest.hex(manifestBytes), binaryIdentityVerified: true)
let dylibID = UUID(), plistID = UUID()
let plans = [
    HelperClosedExecutionPlan(requestID: dylibID, pluginID: proof.pluginID, action: .copyFile,
        sourceRelativePath: "task/Demo.dylib", destinationRelativePath: "Demo.dylib", expectedSHA256: dylibHash, operation: .installDylib),
    HelperClosedExecutionPlan(requestID: plistID, pluginID: proof.pluginID, action: .copyFile,
        sourceRelativePath: "task/Demo.plist", destinationRelativePath: "Demo.plist", expectedSHA256: plistHash, operation: .replaceFilterPlist)
]
let roots = try HelperSafeFileExecutor.Roots(stagingRoot: staging.path, targetDirectory: target.path, expectedStagingUID: UInt32(getuid()))
let executor = HelperSafeFileExecutor(roots: roots)
let receipt = try executor.execute(plans, proof: proof)
try expect(receipt.pluginID == proof.pluginID, "plugin ID receipt mismatch")
let deployedDylib = try Data(contentsOf: target.appendingPathComponent("Demo.dylib"))
let deployedPlist = try Data(contentsOf: target.appendingPathComponent("Demo.plist"))
try expect(deployedDylib == dylibData, "dylib bytes differ")
try expect(deployedPlist == plistData, "plist bytes differ")
try expect(receipt.changedPaths == ["Demo.dylib", "Demo.plist"], "changed path set mismatch")
let targetLeaves = try fm.contentsOfDirectory(atPath: target.path).sorted()
try expect(targetLeaves == ["Demo.dylib", "Demo.plist"], "temporary or backup artifacts remain")

// Existing dylib must block the second transaction without modifying deployed bytes.
do {
    _ = try executor.execute(plans, proof: proof)
    throw NSError(domain: "P1-22", code: 2, userInfo: [NSLocalizedDescriptionKey: "target conflict was not rejected"])
} catch HelperSafeFileExecutor.ExecutorError.targetConflict { }

// Tampered staged bytes must fail hash verification before target mutation.
try writeFile(Data([0x00, 0x01, 0x02]), task.appendingPathComponent("Demo.dylib"))
do {
    _ = try executor.execute(plans, proof: proof)
    throw NSError(domain: "P1-22", code: 4, userInfo: [NSLocalizedDescriptionKey: "tampered staging bytes were accepted"])
} catch HelperSafeFileExecutor.ExecutorError.sourceHashMismatch { }

// Symlinked staged payload must be rejected by O_NOFOLLOW.
let linkURL = task.appendingPathComponent("Linked.dylib")
try fm.createSymbolicLink(at: linkURL, withDestinationURL: task.appendingPathComponent("Demo.plist"))
let symlinkPlan = [
    HelperClosedExecutionPlan(requestID: UUID(), pluginID: proof.pluginID, action: .copyFile,
        sourceRelativePath: "task/Linked.dylib", destinationRelativePath: "Demo.dylib", expectedSHA256: dylibHash, operation: .installDylib),
    plans[1]
]
do {
    _ = try executor.execute(symlinkPlan, proof: proof)
    throw NSError(domain: "P1-22", code: 5, userInfo: [NSLocalizedDescriptionKey: "staging symlink was accepted"])
} catch HelperSafeFileExecutor.ExecutorError.sourceMissingOrUnsafe { }

// A plan for a different plugin cannot borrow the proof.
let wrongPluginPlans = plans.map { plan in
    HelperClosedExecutionPlan(requestID: plan.requestID, pluginID: UUID(), action: plan.action,
        sourceRelativePath: plan.sourceRelativePath, destinationRelativePath: plan.destinationRelativePath,
        expectedSHA256: plan.expectedSHA256, operation: plan.operation)
}
do {
    _ = try executor.execute(wrongPluginPlans, proof: proof)
    throw NSError(domain: "P1-22", code: 3, userInfo: [NSLocalizedDescriptionKey: "plugin proof mismatch was not rejected"])
} catch HelperSafeFileExecutor.ExecutorError.ownershipProofRequired { }

print("P1-22 executor smoke: PASS (paired install, atomic plist replacement, byte/hash preservation, conflict rejection, staging symlink rejection, proof binding)")
