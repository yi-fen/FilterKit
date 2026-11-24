import Foundation
import Glibc

@main
enum P121Smoke {
    static func main() throws {
        let base = "/tmp/filterkit-p121-\(UUID().uuidString)"
        let helperDir = base + "/Library/FilterKit/Helper"
        try FileManager.default.createDirectory(atPath: helperDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: base) }

        let hash = String(repeating: "a", count: 40)
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "rootless",
            jbRootPath: base, tweakInjectPath: base + "/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/Library/FilterKit/Staging",
            socketPath: helperDir + "/helper.sock", appCDHashes: [hash], helperCDHashes: [hash])
        let manifestURL = URL(fileURLWithPath: helperDir + "/manifest.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        let loaded = try HelperSecureManifestStore().read(path: manifestURL.path)
        precondition(loaded == manifest)

        let symlinkPath = helperDir + "/manifest-link.json"
        try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: manifestURL.path)
        do {
            _ = try HelperSecureManifestStore().read(path: symlinkPath)
            fatalError("symlink manifest unexpectedly accepted")
        } catch HelperSecureManifestStore.StoreError.openFailed { }

        let audit = HelperAuditFileSink(path: helperDir + "/audit.jsonl", maximumBytes: 4096, retainedFiles: 3)
        for index in 0..<12 {
            try audit.append(HelperAuditRecord(outcome: .rejected, reasonCode: "smoke_\(index)",
                output: String(repeating: "x", count: 900)))
        }
        let log = helperDir + "/audit.jsonl"
        let logData = try Data(contentsOf: URL(fileURLWithPath: log))
        precondition(!logData.isEmpty)
        precondition(FileManager.default.fileExists(atPath: log + ".1"))

        let plan = try HelperLifecyclePlan.make(action: .install, jbRoot: base)
        precondition(plan.requiresRootInstaller && !plan.mayRunFromApp)
        precondition(plan.artifacts.first(where: { $0.kind == .manifest })?.modeOctal == "0600")
        print("P1-21 runtime smoke: PASS (manifest root-owned 0600, symlink rejection, audit append/rotation, lifecycle plan)")
    }
}
