import XCTest
@testable import FilterKit

final class ElleKitInspectorTests: XCTestCase {
    func testDpkgStatusParserRequiresInstalledStatus() {
        let text = """
        Package: ellekit
        Status: install ok installed
        Version: 1.2-3
        Architecture: iphoneos-arm64e

        Package: other.package
        Status: install ok installed
        Version: 9.9
        """
        let metadata = DpkgStatusParser.installedMetadata(in: text, sourcePath: "/fixture/status",
                                                          isCurrentStatusDatabase: true)
        XCTAssertEqual(metadata?.package, "ellekit")
        XCTAssertEqual(metadata?.version, "1.2-3")
        XCTAssertEqual(metadata?.architecture, "iphoneos-arm64e")
    }

    func testDpkgStatusParserRejectsUnpackedPackage() {
        let text = """
        Package: ellekit
        Status: install ok unpacked
        Version: 1.2-3
        Architecture: iphoneos-arm64e
        """
        XCTAssertNil(DpkgStatusParser.installedMetadata(in: text, sourcePath: "/fixture/status",
                                                        isCurrentStatusDatabase: true))
    }

    func testBinaryAloneDoesNotInventVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = root.appendingPathComponent("usr/lib/libellekit.dylib")
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: library.path, contents: Data([0xcf, 0xfa, 0xed, 0xfe])))
        defer { try? FileManager.default.removeItem(at: root) }

        let result = ElleKitInspector().inspect(rootPath: root.path, environment: .rootHide,
                                                binaryCandidates: [library.path])
        XCTAssertEqual(result.evidenceStatus, .binaryOnly)
        XCTAssertNil(result.packageMetadata?.version)
        XCTAssertFalse(result.profileIdentityVerified)
        XCTAssertFalse(result.commitVerified)
    }

    func testMatchingVersionDoesNotClaimCommitVerified() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let status = root.appendingPathComponent("var/lib/dpkg/status")
        let library = root.appendingPathComponent("usr/lib/libellekit.dylib")
        try FileManager.default.createDirectory(at: status.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try """
        Package: ellekit
        Status: install ok installed
        Version: 1.2-3
        Architecture: iphoneos-arm64e
        """.write(to: status, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: library.path, contents: Data([0xcf, 0xfa, 0xed, 0xfe])))
        defer { try? FileManager.default.removeItem(at: root) }

        let result = ElleKitInspector().inspect(rootPath: root.path, environment: .rootHide,
                                                binaryCandidates: [library.path])
        XCTAssertEqual(result.evidenceStatus, .installed)
        XCTAssertEqual(result.profileMatch, .unknownFingerprint)
        XCTAssertEqual(result.candidateProfileIdentifier, "roothide-dopamine-ellekit-1.2-3-16e3e7e")
        XCTAssertFalse(result.profileIdentityVerified)
        XCTAssertFalse(result.commitVerified)
    }
    func testStatusOldIsNotTreatedAsCurrentInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldStatus = root.appendingPathComponent("var/lib/dpkg/status-old")
        try FileManager.default.createDirectory(at: oldStatus.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try """
        Package: ellekit
        Status: install ok installed
        Version: 1.2-3
        Architecture: iphoneos-arm64e
        """.write(to: oldStatus, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = ElleKitInspector().inspect(rootPath: root.path, environment: .rootHide,
                                                binaryCandidates: [])
        XCTAssertEqual(result.evidenceStatus, .metadataFallbackOnly)
        XCTAssertFalse(result.profileIdentityVerified)
        XCTAssertFalse(result.commitVerified)
        XCTAssertEqual(result.profileMatch, .unverifiable)
    }

    func testLayoutScannerFindsCompanionAndLaunchDaemonWithoutCallingItInstalled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let companion = root.appendingPathComponent("Library/TweakInject/pspawn.dylib")
        let daemon = root.appendingPathComponent("Library/LaunchDaemons/com.evln.ellekit.startup.plist")
        try FileManager.default.createDirectory(at: companion.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: daemon.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: companion.path, contents: Data([0xcf, 0xfa, 0xed, 0xfe])))
        XCTAssertTrue(FileManager.default.createFile(atPath: daemon.path, contents: Data("plist".utf8)))
        defer { try? FileManager.default.removeItem(at: root) }

        let result = ElleKitInspector().inspect(rootPath: root.path, environment: .rootHide, binaryCandidates: [])
        XCTAssertEqual(result.installationState, .suspected)
        XCTAssertTrue(result.layoutEvidence.contains { $0.kind == .companionDylib && $0.exists })
        XCTAssertTrue(result.layoutEvidence.contains { $0.kind == .launchDaemon && $0.exists })
        XCTAssertFalse(result.layoutEvidence.contains { $0.kind == .mainDylib && $0.isMachO == true })
    }

    func testMainLibraryMustHaveMachOMagic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = root.appendingPathComponent("Library/TweakInject/ellekit.dylib")
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: library.path, contents: Data([0x4d, 0x5a, 0, 0])))
        defer { try? FileManager.default.removeItem(at: root) }

        let result = ElleKitInspector().inspect(rootPath: root.path, environment: .rootHide, binaryCandidates: [library.path])
        XCTAssertEqual(result.installationState, .suspected)
        XCTAssertEqual(result.layoutEvidence.first(where: { $0.path == library.path })?.isMachO, false)
    }

    func testDpkgParserPreservesPackageIdentityFieldsAndContinuation() {
        let text = """
        Package: ellekit
        Status: install ok installed
        Version: 1.2.3-palera1n
        Architecture: iphoneos-arm64e
        Maintainer: Example Maintainer <maintainer@example.invalid>
        Origin: RootHide
        Homepage: https://example.invalid/ellekit
        Description: ElleKit injection platform
         second description line

        """
        let metadata = DpkgStatusParser.installedMetadata(in: text, sourcePath: "/fixture/status",
                                                          isCurrentStatusDatabase: true)
        XCTAssertEqual(metadata?.version, "1.2.3-palera1n")
        XCTAssertEqual(metadata?.maintainer, "Example Maintainer <maintainer@example.invalid>")
        XCTAssertEqual(metadata?.origin, "RootHide")
        XCTAssertEqual(metadata?.homepage, "https://example.invalid/ellekit")
    }

    func testMachOReaderParsesDylibIDAndUUID() throws {
        var bytes = Data()
        func append32(_ value: UInt32) { bytes.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }
        // 64-bit little-endian Mach-O header, two load commands, 56 command bytes.
        append32(0xFEEDFACF); append32(0x0100000C); append32(0); append32(6)
        append32(2); append32(80); append32(0); append32(0)
        // LC_ID_DYLIB (24 bytes header + 16-byte NUL-terminated name)
        append32(0xD); append32(56); append32(24); append32(0); append32(0x00010002); append32(0x00010000)
        bytes.append(contentsOf: Array("/usr/lib/libellekit.dylib".utf8) + [0])
        // Pad command to 40 bytes (name is 25 bytes incl NUL)
        while bytes.count < 32 + 56 { bytes.append(0) }
        // LC_UUID
        append32(0x1B); append32(24)
        bytes.append(contentsOf: Array(0...15).map(UInt8.init))

        let parsed = try MachOMetadataReader().read(data: bytes, architecture: "arm64e")
        XCTAssertEqual(parsed.installName, "/usr/lib/libellekit.dylib")
        XCTAssertEqual(parsed.currentVersion, "1.0.2")
        XCTAssertEqual(parsed.compatibilityVersion, "1.0.0")
        XCTAssertEqual(parsed.uuid, "000102030405060708090a0b0c0d0e0f")
        XCTAssertTrue(parsed.is64Bit)
        XCTAssertEqual(parsed.architecture, "arm64e")
    }

    func testMachOReaderRejectsNonMachOAndTruncatedCommands() {
        XCTAssertThrowsError(try MachOMetadataReader().read(data: Data([0x4d, 0x5a, 0, 0])))
        XCTAssertThrowsError(try MachOMetadataReader().read(data: Data([0xcf, 0xfa, 0xed, 0xfe])))
    }

    func testPackedMachOVersionFormatting() {
        XCTAssertEqual(MachOMetadataReader.formatPackedVersion(0x010203), "1.2.3")
    }


    func testCurrentAndBackupStatusDatabaseDisagreementIsReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = root.appendingPathComponent("var/lib/dpkg/status")
        let old = root.appendingPathComponent("var/lib/dpkg/status-old")
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try """
        Package: ellekit
        Status: install ok installed
        Version: 1.2-3
        Architecture: iphoneos-arm64e
        """.write(to: current, atomically: true, encoding: .utf8)
        try """
        Package: ellekit
        Status: install ok installed
        Version: 1.1-0
        Architecture: iphoneos-arm64
        """.write(to: old, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = ElleKitInspector().inspect(rootPath: root.path, environment: .rootHide,
                                                binaryCandidates: [])
        XCTAssertEqual(result.packageMetadata?.version, "1.2-3")
        XCTAssertTrue(result.warnings.contains("environment.ellekit.status_database_conflict"))
    }

}
