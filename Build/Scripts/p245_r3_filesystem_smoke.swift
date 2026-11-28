import Foundation
import Glibc

struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable { case executable, deploymentManifest, launchDaemon }
    static let activeReleasePointerPath = "Library/FilterKit/Helper/active-release.json"
}

@main struct P245R3FilesystemSmoke {
    static var passed = 0
    static var failed = 0
    static func check(_ name: String, _ body: () throws -> Bool) {
        do {
            if try body() { passed += 1; print("PASS \(name)") }
            else { failed += 1; print("FAIL \(name)") }
        } catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func expectObserverError(_ observer: HelperInstallerDescriptorFilesystemObserver,
                                    path: String, privateFile: Bool = false,
                                    matches: (HelperInstallerDescriptorFilesystemObserver.ObservationError) -> Bool) -> Bool {
        do { _ = try observer.observeFile(relativePath: path, privateFile: privateFile); return false }
        catch let error as HelperInstallerDescriptorFilesystemObserver.ObservationError { return matches(error) }
        catch { return false }
    }
    static func main() throws {
        let fm = FileManager.default
        let root = "/root/filterkit-p245-r3-\(UUID().uuidString)"
        try fm.createDirectory(atPath: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(atPath: root) }
        _ = chmod(root, 0o700)
        let uid = UInt32(getuid())
        let observer = HelperInstallerDescriptorFilesystemObserver(jbRootPath: root, expectedOwnerUID: uid)
        let lib = root + "/usr/libexec"
        let manifest = root + "/Library/FilterKit/Helper"
        let launch = root + "/Library/LaunchDaemons"
        try fm.createDirectory(atPath: lib, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: manifest, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: launch, withIntermediateDirectories: true)
        for dir in [root + "/usr", root + "/usr/libexec", root + "/Library", root + "/Library/FilterKit", manifest, launch] { _ = chmod(dir, 0o700) }
        let paths: [HelperRootReleaseSet.Artifact: String] = [
            .executable: "usr/libexec/filterkit-helper",
            .deploymentManifest: "Library/FilterKit/Helper/Deployment.json",
            .launchDaemon: "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
        ]
        let values: [HelperRootReleaseSet.Artifact: Data] = [
            .executable: Data("helper-binary-fixture".utf8),
            .deploymentManifest: Data("{\"schema\":2}".utf8),
            .launchDaemon: Data("launchd-fixture".utf8)
        ]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            try values[artifact]!.write(to: URL(fileURLWithPath: root + "/" + paths[artifact]!))
            _ = chmod(root + "/" + paths[artifact]!, 0o600)
        }
        check("regular artifact hash and metadata") {
            let record = try observer.observeFile(relativePath: paths[.executable]!)
            return record.sha256 == SHA256Digest.hex(values[.executable]!) && record.byteCount == values[.executable]!.count && record.ownerUID == uid && record.mode == 0o600
        }
        check("complete three-artifact observation") {
            let records = try observer.observeArtifactSet(paths: paths)
            return records.count == 3 && records[.launchDaemon]?.sha256 == SHA256Digest.hex(values[.launchDaemon]!)
        }
        check("missing leaf is explicitly missing") {
            let states = try observer.observeArtifactSetAllowingMissing(paths: [
                .executable: paths[.executable]!, .deploymentManifest: "Library/FilterKit/Helper/missing.json", .launchDaemon: paths[.launchDaemon]!
            ])
            if case .missing = states[.deploymentManifest]! { return true }; return false
        }
        check("missing parent is explicitly missing") {
            let states = try observer.observeArtifactSetAllowingMissing(paths: [
                .executable: paths[.executable]!, .deploymentManifest: "absent/child/file", .launchDaemon: paths[.launchDaemon]!
            ])
            if case .missing = states[.deploymentManifest]! { return true }; return false
        }
        for invalid in ["", "/etc/passwd", "../escape", "a/../b", "a//b", "a/./b", "a\\b", "a\0b"] {
            check("reject unsafe relative path \(invalid.debugDescription)") {
                expectObserverError(observer, path: invalid) { if case .invalidRelativePath = $0 { return true }; return false }
            }
        }
        let symlinkFile = root + "/Library/FilterKit/Helper/symlink.json"
        _ = symlinkFile.withCString { target in (root + "/Library/FilterKit/Helper/Deployment.json").withCString { link($0, target) } }
        check("reject leaf symlink") {
            expectObserverError(observer, path: "Library/FilterKit/Helper/symlink.json") { if case .unsafeFile = $0 { return true }; return false }
        }
        let symlinkDir = root + "/alias"
        _ = symlinkDir.withCString { dst in manifest.withCString { symlink($0, dst) } }
        check("reject intermediate symlink") {
            expectObserverError(observer, path: "alias/Deployment.json") { if case .openFailed = $0 { return true }; return false }
        }
        let hardlink = root + "/Library/FilterKit/Helper/hardlink.json"
        _ = (root + "/Library/FilterKit/Helper/Deployment.json").withCString { src in hardlink.withCString { dst in Glibc.link(src, dst) } }
        check("reject hard-linked file") {
            expectObserverError(observer, path: "Library/FilterKit/Helper/hardlink.json") { if case .unsafeFile = $0 { return true }; return false }
        }
        let writableFile = root + "/Library/FilterKit/Helper/writable.json"
        try Data("writable".utf8).write(to: URL(fileURLWithPath: writableFile)); _ = chmod(writableFile, 0o660)
        check("reject group-writable file") {
            expectObserverError(observer, path: "Library/FilterKit/Helper/writable.json") { if case .unsafeFile = $0 { return true }; return false }
        }
        let privateFile = root + "/Library/FilterKit/Helper/private.json"
        try Data("private".utf8).write(to: URL(fileURLWithPath: privateFile)); _ = chmod(privateFile, 0o600)
        check("private-file mode accepted") { try observer.observeFile(relativePath: "Library/FilterKit/Helper/private.json", privateFile: true).mode == 0o600 }
        _ = chmod(privateFile, 0o640)
        check("private-file rejects group read") {
            expectObserverError(observer, path: "Library/FilterKit/Helper/private.json", privateFile: true) { if case .unsafeFile = $0 { return true }; return false }
        }
        _ = chmod(manifest, 0o777)
        check("reject writable intermediate directory") {
            expectObserverError(observer, path: "Library/FilterKit/Helper/Deployment.json") { if case .unsafeDirectory = $0 { return true }; return false }
        }
        _ = chmod(manifest, 0o700)
        check("root rejects writable root directory") {
            _ = chmod(root, 0o777)
            let bad = HelperInstallerDescriptorFilesystemObserver(jbRootPath: root, expectedOwnerUID: uid)
            let result = expectObserverError(bad, path: paths[.executable]!) { if case .unsafeDirectory = $0 { return true }; return false }
            _ = chmod(root, 0o700)
            return result
        }
        check("missing file is not confused with permission/type failure") {
            let fifo = root + "/Library/FilterKit/Helper/fifo"
            _ = fifo.withCString { mkfifo($0, 0o600) }
            defer { _ = unlink(fifo) }
            return expectObserverError(observer, path: "Library/FilterKit/Helper/fifo") { if case .unsafeFile = $0 { return true }; return false }
        }
        check("reject wrong-owner artifact") {
            let wrongOwner = root + "/Library/FilterKit/Helper/wrong-owner"
            try Data("owner".utf8).write(to: URL(fileURLWithPath: wrongOwner)); _ = chmod(wrongOwner, 0o600)
            _ = chown(wrongOwner, 65534, 65534)
            return expectObserverError(observer, path: "Library/FilterKit/Helper/wrong-owner") { if case .unsafeFile = $0 { return true }; return false }
        }
        check("reject wrong-owner nested directory") {
            let wrongDir = root + "/Library/FilterKit/Helper/wrong-owner-dir"
            try fm.createDirectory(atPath: wrongDir, withIntermediateDirectories: false); _ = chmod(wrongDir, 0o700)
            _ = chown(wrongDir, 65534, 65534)
            return expectObserverError(observer, path: "Library/FilterKit/Helper/wrong-owner-dir/file") { if case .unsafeDirectory = $0 { return true }; return false }
        }
        check("oversized artifact rejected") {
            let big = root + "/Library/FilterKit/Helper/big"
            try Data(repeating: 0x41, count: 8192).write(to: URL(fileURLWithPath: big)); _ = chmod(big, 0o600)
            let limited = HelperInstallerDescriptorFilesystemObserver(jbRootPath: root, expectedOwnerUID: uid, maximumArtifactBytes: 4096)
            return expectObserverError(limited, path: "Library/FilterKit/Helper/big") { if case .oversized = $0 { return true }; return false }
        }
        print("SUMMARY passed=\(passed) failed=\(failed)")
        if failed > 0 { exit(1) }
    }
}
