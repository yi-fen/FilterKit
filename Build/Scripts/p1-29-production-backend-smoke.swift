import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func expect129(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-29-backend", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func le32_129(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
}
@main struct P129ProductionBackendSmoke {
    static func main() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-29-backend-\(UUID().uuidString)", isDirectory: true)
        let target = base.appendingPathComponent("TweakInject", isDirectory: true)
        let staging = base.appendingPathComponent("Staging", isDirectory: true)
        let task = staging.appendingPathComponent("task", isDirectory: true)
        let info = base.appendingPathComponent("dpkg-info", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try fm.createDirectory(at: task, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: info, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        defer { try? fm.removeItem(at: base) }

        var macho = [UInt8]()
        macho += [0xcf, 0xfa, 0xed, 0xfe]
        macho += le32_129(0x0100000c) + le32_129(0) + le32_129(6) + le32_129(1) + le32_129(24) + le32_129(0) + le32_129(0)
        macho += le32_129(0x1b) + le32_129(24) + Array(1...16).map(UInt8.init)
        let dylib = Data(macho)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.source"]]], format: .xml, options: 0)
        let dylibURL = task.appendingPathComponent("Demo.dylib"), plistURL = task.appendingPathComponent("Demo.plist")
        try dylib.write(to: dylibURL); try plist.write(to: plistURL)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dylibURL.path)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)

        let pluginID = UUID(), now = Date()
        let operations = [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
                expectedSHA256: SHA256Digest.hex(dylib), createdAt: now),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Demo.plist", targetFileName: "Demo.plist",
                expectedSHA256: SHA256Digest.hex(plist), createdAt: now)
        ]
        let metadata = HelperDeploymentBatchMetadata(hardBoundBundleIdentifier: "com.example.source", softAssociations: [])
        let batch = try HelperDeploymentBatchRequest.make(pluginID: pluginID, operations: operations,
            deploymentMetadata: metadata, createdAt: now)
        let identity = HelperPeerIdentity(uid: UInt32(getuid()), gid: UInt32(getgid()), pid: getpid(),
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        let context = HelperAuthenticatedPeerContext(peer: .init(uid: identity.uid, gid: identity.gid, pid: identity.pid),
            identity: identity, sessionNonce: String(repeating: "b", count: 32), authenticatedAt: now)
        let config = try HelperProductionDeploymentBackend.Configuration(pluginDirectory: target.path,
            stagingRoot: staging.path, stagingOwnerUID: UInt32(getuid()), dpkgInfoDirectories: [info.path])
        let backend = try HelperProductionDeploymentBackend(configuration: config)
        let evidence = try backend.inspectRoute(batch: batch, context: context)
        try expect129(!evidence.manifestExists && evidence.ownership == .verifiedUnowned, "first-install route evidence incorrect")
        let prepared = try backend.authorizeFirstInstall(batch: batch, context: context)
        try expect129(prepared.proof.isFirstInstallAuthorization && prepared.proof.pluginID == pluginID, "first-install proof mismatch")
        try expect129(prepared.plans.count == 2, "paired execution plans missing")
        do {
            _ = try backend.execute(prepared)
            throw NSError(domain: "P1-29-backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "execution gate unexpectedly opened"])
        } catch HelperProductionDeploymentBackend.BackendError.executionNotReleased { }
        let targetLeaves = try fm.contentsOfDirectory(atPath: target.path)
        try expect129(targetLeaves.isEmpty, "preflight mutated target directory")

        let ownedList = info.appendingPathComponent("foreign-package.list")
        try Data((target.path + "/Demo.dylib\n").utf8).write(to: ownedList)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ownedList.path)
        let ownedEvidence = try backend.inspectRoute(batch: batch, context: context)
        try expect129(ownedEvidence.ownership == .packageManagerOwned, "dpkg ownership was not detected")
        print("P1-29 production backend smoke: PASS (real staging read, Mach-O/plist validation, package ownership, route evidence, mutation gate closed)")
    }
}
