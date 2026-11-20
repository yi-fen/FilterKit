//
//  PermissionProbeProbeTests.swift
//  FilterKit Stage 2 — PermissionProbe D2～D7（探针链路）
//
//  合成桩覆盖：JBROOT / ElleKit 目录访问、插件文件元数据、plist 读取复用
//  Reader、dpkg 只读、entitlement/sandbox、jbroot() API 接缝、统一服务异常
//  隔离。不触碰真机文件系统；权限拒绝/不存在以错误域码桩模拟。
//

import Foundation
import XCTest
@testable import Core
@testable import Models

final class PermissionProbeProbeTests: XCTestCase {

    // MARK: - 桩

    private final class FakeFileAccess: FileAccessChecking {
        var inspectResult: FileAccessResult
        var entries: [URL]
        var data: Data
        var listError: Error?
        var readError: Error?

        init(inspectResult: FileAccessResult,
             entries: [URL] = [],
             data: Data = Data(),
             listError: Error? = nil,
             readError: Error? = nil) {
            self.inspectResult = inspectResult
            self.entries = entries
            self.data = data
            self.listError = listError
            self.readError = readError
        }

        func inspect(_ url: URL) -> FileAccessResult { inspectResult }
        func listDirectory(_ url: URL) throws -> [URL] {
            if let listError { throw listError }
            return entries
        }
        func read(_ url: URL) throws -> Data {
            if let readError { throw readError }
            return data
        }
    }

    private final class FakePlistReader: PlistDataReading {
        var result: PlistReadResult
        init(result: PlistReadResult) { self.result = result }
        func read(path: String) -> PlistReadResult { result }
    }

    private final class FakeEntitlementInspector: EntitlementInspecting {
        var snapshot: EntitlementSnapshot
        init(snapshot: EntitlementSnapshot) { self.snapshot = snapshot }
        func inspectProcessEntitlements() -> EntitlementSnapshot { snapshot }
    }

    private final class FakeCodeSignInspector: CodeSignInspecting {
        var snapshot: EntitlementSnapshot
        init(snapshot: EntitlementSnapshot) { self.snapshot = snapshot }
        func inspectCodeSignEntitlements() -> EntitlementSnapshot { snapshot }
    }

    private final class FakeJBRootResolver: JBRootResolving {
        var snapshot: JBRootAPISnapshot
        init(snapshot: JBRootAPISnapshot) { self.snapshot = snapshot }
        func resolveJBRootViaAPI() -> JBRootAPISnapshot { snapshot }
    }

    private struct ThrowingProbe: PermissionProbing {
        let probeID: String
        func run() throws -> [ProbeEvidence] {
            throw NSError(domain: "test-probe", code: 99)
        }
    }

    private static func posix(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    // MARK: - D2 JBROOT

    func testJBRootProbeNotExecutedWhenNoConfirmedPath() {
        let probe = JBRootProbe(confirmedJBRoot: nil,
                                fileAccess: FakeFileAccess(inspectResult: FileAccessResult(exists: false)))
        let evidence = probe.run()
        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence.first?.status, .notExecuted)
        XCTAssertEqual(evidence.first?.category, .jbroot)
    }

    func testJBRootProbePassesDirectoryWithEntries() {
        let entries = [URL(fileURLWithPath: "/a.dylib"), URL(fileURLWithPath: "/b.plist")]
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: true),
            entries: entries
        )
        let probe = JBRootProbe(confirmedJBRoot: "/private/var/jb", fileAccess: checker)
        let evidence = probe.run()

        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(evidence[0].status, .passed)
        XCTAssertEqual(evidence[0].operation, .stat)
        XCTAssertEqual(evidence[1].status, .passed)
        XCTAssertEqual(evidence[1].operation, .list)
        XCTAssertEqual(evidence[1].observedValue, "entries: 2")
    }

    func testJBRootProbeClassifiesMissingAsUnavailable() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: false,
                                            errorDomain: NSPOSIXErrorDomain,
                                            errorCode: 2,
                                            errno: POSIXErrorCode.ENOENT.rawValue)
        )
        let probe = JBRootProbe(confirmedJBRoot: "/private/var/jb", fileAccess: checker)
        let evidence = probe.run()

        XCTAssertEqual(evidence[0].status, .unavailable)
        XCTAssertEqual(evidence[1].status, .notExecuted)
    }

    func testJBRootProbeClassifiesDenied() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: false,
                                            errorDomain: NSPOSIXErrorDomain,
                                            errorCode: 13,
                                            errno: POSIXErrorCode.EACCES.rawValue)
        )
        let probe = JBRootProbe(confirmedJBRoot: "/private/var/jb", fileAccess: checker)
        let evidence = probe.run()
        XCTAssertEqual(evidence[0].status, .permissionDenied)
    }

    // MARK: - D3 ElleKit

    func testElleKitProbeNotExecutedWhenNoResolvedPath() {
        let probe = ElleKitDirectoryProbe(
            resolvedDirectory: nil,
            route: "roothide",
            fileAccess: FakeFileAccess(inspectResult: FileAccessResult(exists: false))
        )
        let evidence = probe.run()
        XCTAssertEqual(evidence.first?.status, .notExecuted)
        XCTAssertEqual(evidence.first?.category, .ellekit)
    }

    func testElleKitProbeDirectoryPassesAndLists() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: true, isSymlink: false),
            entries: [URL(fileURLWithPath: "/x.dylib")]
        )
        let probe = ElleKitDirectoryProbe(
            resolvedDirectory: "/private/var/jb/usr/lib/TweakInject",
            route: "roothide",
            fileAccess: checker
        )
        let evidence = probe.run()

        XCTAssertEqual(evidence.count, 3)
        XCTAssertEqual(evidence[0].status, .passed)
        XCTAssertEqual(evidence[1].status, .passed)
        XCTAssertEqual(evidence[1].observedValue, "not-symlink")
        XCTAssertEqual(evidence[2].status, .passed)
        XCTAssertEqual(evidence[2].observedValue, "entries: 1")
    }

    func testElleKitProbeSymlinkTargetReachable() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: true, isSymlink: true),
            entries: []
        )
        let probe = ElleKitDirectoryProbe(
            resolvedDirectory: "/usr/lib/TweakInject",
            route: "rootless",
            fileAccess: checker
        )
        let evidence = probe.run()
        let resolve = evidence.first { $0.probeID == "ellekit.directory.symlink" }
        XCTAssertEqual(resolve?.status, .passed)
        XCTAssertEqual(resolve?.observedValue, "symlink-target-reachable")
    }

    // MARK: - D4 Plugin File / Plist / Dpkg

    func testPluginFileProbePassesExistingFile() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: false)
        )
        let probe = PluginFileProbe(dylibPaths: ["/tweak/lib.dylib"], fileAccess: checker)
        let evidence = probe.run()
        XCTAssertEqual(evidence.first?.status, .passed)
        XCTAssertEqual(evidence.first?.operation, .stat)
        XCTAssertEqual(evidence.first?.category, .pluginFiles)
    }

    func testPluginFileProbeFailsWhenDirectory() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: true)
        )
        let probe = PluginFileProbe(dylibPaths: ["/tweak"], fileAccess: checker)
        XCTAssertEqual(probe.run().first?.status, .failed)
    }

    func testPluginFileProbeNotExecutedWhenEmpty() {
        let probe = PluginFileProbe(dylibPaths: [],
                                    fileAccess: FakeFileAccess(inspectResult: FileAccessResult(exists: false)))
        XCTAssertEqual(probe.run().first?.status, .notExecuted)
    }

    func testPlistReadProbeMapsReaderStatuses() {
        let success = PlistReadResult(status: .success, data: Data([1, 2, 3]), path: "/a.plist")
        let missing = PlistReadResult(status: .notFound, data: nil, path: "/b.plist", errorCode: 2)
        let denied = PlistReadResult(status: .accessDenied, data: nil, path: "/c.plist", errorCode: 13)
        let failed = PlistReadResult(status: .readFailed, data: nil, path: "/d.plist", errorCode: 22)

        let probe = PlistReadProbe(
            plistPaths: ["/a.plist", "/b.plist", "/c.plist", "/d.plist"],
            reader: FakePlistReader(result: success)
        )
        // 逐路径替换结果验证映射
        let cases: [(PlistReadResult, ProbeStatus)] = [
            (success, .passed),
            (missing, .unavailable),
            (denied, .permissionDenied),
            (failed, .failed)
        ]
        for (result, expected) in cases {
            let single = PlistReadProbe(plistPaths: [result.path],
                                         reader: FakePlistReader(result: result))
            XCTAssertEqual(single.run().first?.status, expected)
        }
        XCTAssertEqual(probe.run().first?.observedValue, "data-readable: 3 bytes")
    }

    func testPlistReadProbeNotExecutedWhenEmpty() {
        let probe = PlistReadProbe(plistPaths: [],
                                   reader: FakePlistReader(result: PlistReadResult(status: .success, data: nil, path: "")))
        XCTAssertEqual(probe.run().first?.status, .notExecuted)
    }

    func testDpkgProbePassesNonEmptyStatusFile() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: false),
            data: Data("Package: x\n".utf8)
        )
        let probe = DpkgDatabaseProbe(statusFilePath: "/var/lib/dpkg/status", fileAccess: checker)
        let evidence = probe.run()
        XCTAssertEqual(evidence[0].status, .passed)
        XCTAssertEqual(evidence[1].status, .passed)
        XCTAssertEqual(evidence[1].observedValue, "readable: 11 bytes")
    }

    func testDpkgProbeFailsEmptyFile() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: false),
            data: Data()
        )
        let probe = DpkgDatabaseProbe(statusFilePath: "/var/lib/dpkg/status", fileAccess: checker)
        XCTAssertEqual(probe.run()[1].status, .failed)
    }

    func testDpkgProbeNotExecutedWhenNoPath() {
        let probe = DpkgDatabaseProbe(statusFilePath: nil,
                                      fileAccess: FakeFileAccess(inspectResult: FileAccessResult(exists: false)))
        XCTAssertEqual(probe.run().first?.status, .notExecuted)
    }

    // MARK: - D5 Entitlement / Sandbox

    func testEntitlementProbeUnavailableWhenInspectorsUnavailable() {
        let probe = EntitlementProbe(
            processInspector: UnavailableEntitlementInspector(),
            codeSignInspector: UnavailableCodeSignInspector()
        )
        let evidence = probe.run()
        XCTAssertEqual(evidence.count, 2)
        XCTAssertTrue(evidence.allSatisfy { $0.status == .unavailable })
        XCTAssertTrue(evidence.allSatisfy { $0.category == .entitlement })
    }

    func testEntitlementProbeAvailableRecordsKeyCountOnly() {
        let probe = EntitlementProbe(
            processInspector: FakeEntitlementInspector(
                snapshot: EntitlementSnapshot(available: true, observedKeys: ["keychain-access-groups"])
            ),
            codeSignInspector: FakeCodeSignInspector(
                snapshot: EntitlementSnapshot(available: true, observedKeys: [])
            )
        )
        let evidence = probe.run()
        XCTAssertEqual(evidence[0].status, .passed)
        XCTAssertEqual(evidence[0].observedValue, "[runtime] entitlement keys: 1")
        XCTAssertEqual(evidence[1].status, .passed)
        XCTAssertEqual(evidence[1].observedValue, "[signed] entitlement keys: 0")
    }

    func testEntitlementProbeTagsRuntimeAndSignedSourcesSeparately() {
        let probe = EntitlementProbe(
            processInspector: FakeEntitlementInspector(
                snapshot: EntitlementSnapshot(available: true, observedKeys: ["task-for-pid-entitlement"])
            ),
            codeSignInspector: FakeCodeSignInspector(
                snapshot: EntitlementSnapshot(available: false, reason: "code-sign not verified")
            )
        )
        let evidence = probe.run()
        XCTAssertEqual(evidence.count, 2)
        XCTAssertTrue(evidence.allSatisfy { $0.category == .entitlement })
        XCTAssertTrue(evidence[0].observedValue?.hasPrefix("[runtime] ") == true)
        XCTAssertTrue(evidence[1].observedValue?.hasPrefix("[signed] ") == true)
        XCTAssertEqual(evidence[0].status, .passed)
        XCTAssertEqual(evidence[1].status, .unavailable)
    }

    func testEntitlementProbeRuntimeUnavailableRecordsPlatformReason() {
        let probe = EntitlementProbe(
            processInspector: UnavailableEntitlementInspector(),
            codeSignInspector: UnavailableCodeSignInspector()
        )
        let evidence = probe.run()
        let runtime = evidence.first { $0.probeID == "entitlement.process" }
        let signed = evidence.first { $0.probeID == "entitlement.code-sign" }
        XCTAssertEqual(runtime?.status, .unavailable)
        XCTAssertEqual(signed?.status, .unavailable)
        XCTAssertTrue(runtime?.observedValue?.contains("macOS/Catalyst") == true)
        XCTAssertTrue(runtime?.observedValue?.hasPrefix("[runtime] ") == true)
        XCTAssertTrue(signed?.observedValue?.hasPrefix("[signed] ") == true)
    }

    func testEntitlementEvidenceSourceCoversThreeSeparateClasses() {
        XCTAssertEqual(EntitlementEvidenceSource.signed.rawValue, "signed")
        XCTAssertEqual(EntitlementEvidenceSource.runtime.rawValue, "runtime")
        XCTAssertEqual(EntitlementEvidenceSource.resourceAccess.rawValue, "resourceAccess")
        let record = EntitlementEvidenceRecord(source: .resourceAccess, available: false, reason: "denied")
        XCTAssertEqual(record.source, .resourceAccess)
        XCTAssertFalse(record.available)
    }

    func testSandboxProbeReachableAndUnreachable() {
        let reachable = FakeFileAccess(inspectResult: FileAccessResult(exists: true))
        let missing = FakeFileAccess(
            inspectResult: FileAccessResult(exists: false,
                                            errorDomain: NSPOSIXErrorDomain,
                                            errorCode: 2)
        )
        let probe = SandboxAccessProbe(
            targets: [
                SandboxTarget(label: "jbroot", path: "/private/var/jb"),
                SandboxTarget(label: "hidden", path: "/private/var/mobile")
            ],
            fileAccess: reachable
        )
        // 第二个目标使用缺失桩：通过分别构造验证分类
        let reachableEvidence = SandboxAccessProbe(
            targets: [SandboxTarget(label: "jbroot", path: "/private/var/jb")],
            fileAccess: reachable
        ).run()
        let missingEvidence = SandboxAccessProbe(
            targets: [SandboxTarget(label: "hidden", path: "/private/var/mobile")],
            fileAccess: missing
        ).run()
        XCTAssertEqual(reachableEvidence.first?.status, .passed)
        XCTAssertEqual(missingEvidence.first?.status, .unavailable)
        XCTAssertEqual(probe.run().count, 2)
    }

    func testSandboxProbeNotExecutedWhenEmpty() {
        let probe = SandboxAccessProbe(
            targets: [],
            fileAccess: FakeFileAccess(inspectResult: FileAccessResult(exists: false))
        )
        XCTAssertEqual(probe.run().first?.status, .notExecuted)
    }

    // MARK: - D6 jbroot() API

    func testJBRootAPIProbePlaceholderAllUnknown() {
        let probe = JBRootAPIProbe(resolver: UnavailableJBRootResolver(), confirmedJBRoot: nil)
        let evidence = probe.run()
        XCTAssertEqual(evidence.count, 4)
        XCTAssertEqual(evidence[0].status, .unavailable)
        XCTAssertEqual(evidence[1].status, .unavailable)
        XCTAssertEqual(evidence[2].status, .unknown)
        XCTAssertEqual(evidence[3].status, .unknown)
    }

    func testJBRootAPIProbeConsistencyMatchesConfirmedPath() {
        let resolver = FakeJBRootResolver(
            snapshot: JBRootAPISnapshot(
                symbolAvailable: true,
                invoked: true,
                resolvedPath: "/private/var/jb"
            )
        )
        let probe = JBRootAPIProbe(resolver: resolver, confirmedJBRoot: "/private/var/jb")
        let evidence = probe.run()
        XCTAssertEqual(evidence[0].status, .passed)
        XCTAssertEqual(evidence[1].status, .passed)
        XCTAssertEqual(evidence[2].status, .passed)
        XCTAssertEqual(evidence[3].status, .passed)
        XCTAssertTrue(evidence[3].observedValue?.contains("normalized-match:true") == true)
        XCTAssertTrue(evidence[3].observedValue?.contains("accessible:unknown") == true)
    }

    func testJBRootAPIProbeConsistencyMismatchFails() {
        let resolver = FakeJBRootResolver(
            snapshot: JBRootAPISnapshot(
                symbolAvailable: true,
                invoked: true,
                resolvedPath: "/var/jb"
            )
        )
        let probe = JBRootAPIProbe(resolver: resolver, confirmedJBRoot: "/private/var/jb")
        let consistency = probe.run().first { $0.probeID == "jbroot-api.consistency" }
        XCTAssertEqual(consistency?.status, .failed)
        XCTAssertTrue(consistency?.observedValue?.contains("normalized-match:false") == true)
    }

    func testJBRootComparatorNormalizesTrailingSlashDoubleSlashDotDot() {
        let comparison = JBRootPathComparator.compare(
            returned: "/private/var/jb/",
            confirmed: "/private//var/./jb/../jb"
        )
        XCTAssertEqual(comparison.returnedNormalized, "/private/var/jb")
        XCTAssertEqual(comparison.confirmedNormalized, "/private/var/jb")
        XCTAssertEqual(comparison.rawMatch, false)
        XCTAssertEqual(comparison.normalizedMatch, true)
        XCTAssertEqual(JBRootPathComparator.verdict(comparison), .passed)
    }

    func testJBRootAPIProbeNormalizedMatchDespiteRawDifferences() {
        let resolver = FakeJBRootResolver(
            snapshot: JBRootAPISnapshot(
                symbolAvailable: true,
                invoked: true,
                resolvedPath: "/private/var/jb/"
            )
        )
        let probe = JBRootAPIProbe(resolver: resolver, confirmedJBRoot: "/private//var/./jb")
        let consistency = probe.run().first { $0.probeID == "jbroot-api.consistency" }
        XCTAssertEqual(consistency?.status, .passed)
        XCTAssertTrue(consistency?.observedValue?.contains("raw-match:false") == true)
        XCTAssertTrue(consistency?.observedValue?.contains("normalized-match:true") == true)
    }

    func testJBRootAPIProbeAccessibleLayerUnknownWithoutFileAccess() {
        let comparison = JBRootPathComparator.compare(
            returned: "/private/var/jb",
            confirmed: "/private/var/jb",
            fileAccess: nil
        )
        XCTAssertNil(comparison.accessibleMatch)
    }

    func testJBRootAPIProbeAccessibleMatchWithFileAccess() {
        let checker = FakeFileAccess(inspectResult: FileAccessResult(exists: true, isDirectory: true))
        let resolver = FakeJBRootResolver(
            snapshot: JBRootAPISnapshot(
                symbolAvailable: true,
                invoked: true,
                resolvedPath: "/private/var/jb"
            )
        )
        let probe = JBRootAPIProbe(resolver: resolver,
                                   confirmedJBRoot: "/private/var/jb",
                                   fileAccess: checker)
        let consistency = probe.run().first { $0.probeID == "jbroot-api.consistency" }
        XCTAssertEqual(consistency?.status, .passed)
        XCTAssertTrue(consistency?.observedValue?.contains("accessible:true") == true)
    }

    func testJBRootAPIProbeAccessibleFalseWhenUnreachable() {
        let checker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: false,
                                            errorDomain: NSPOSIXErrorDomain,
                                            errorCode: 2)
        )
        let resolver = FakeJBRootResolver(
            snapshot: JBRootAPISnapshot(
                symbolAvailable: true,
                invoked: true,
                resolvedPath: "/private/var/jb"
            )
        )
        let probe = JBRootAPIProbe(resolver: resolver,
                                   confirmedJBRoot: "/private/var/jb",
                                   fileAccess: checker)
        let consistency = probe.run().first { $0.probeID == "jbroot-api.consistency" }
        // 可达性是独立证据层：不反向改写一致性 verdict；摘要保留 accessible:false。
        XCTAssertEqual(consistency?.status, .passed)
        XCTAssertTrue(consistency?.observedValue?.contains("accessible:false") == true)
    }

    func testJBRootAPIProbeUnknownWhenConfirmedPathMissing() {
        let resolver = FakeJBRootResolver(
            snapshot: JBRootAPISnapshot(
                symbolAvailable: true,
                invoked: true,
                resolvedPath: "/private/var/jb"
            )
        )
        let probe = JBRootAPIProbe(resolver: resolver, confirmedJBRoot: nil)
        let consistency = probe.run().first { $0.probeID == "jbroot-api.consistency" }
        XCTAssertEqual(consistency?.status, .unknown)
        XCTAssertTrue(consistency?.observedValue?.contains("normalized-match:unknown") == true)
    }

    func testJBRootComparatorVerdictRules() {
        let normalizedMismatch = JBRootPathComparison(
            returnedRaw: "/a", confirmedRaw: "/b",
            returnedNormalized: "/a", confirmedNormalized: "/b",
            returnedSymlinkResolved: nil, confirmedSymlinkResolved: nil,
            rawMatch: false, normalizedMatch: false, symlinkMatch: nil, accessibleMatch: nil
        )
        XCTAssertEqual(JBRootPathComparator.verdict(normalizedMismatch), .failed)

        let normalizedMatchSymlinkMismatch = JBRootPathComparison(
            returnedRaw: "/a", confirmedRaw: "/a",
            returnedNormalized: "/a", confirmedNormalized: "/a",
            returnedSymlinkResolved: "/a/real", confirmedSymlinkResolved: "/b/real",
            rawMatch: true, normalizedMatch: true, symlinkMatch: false, accessibleMatch: nil
        )
        XCTAssertEqual(JBRootPathComparator.verdict(normalizedMatchSymlinkMismatch), .failed)

        let normalizedMatchSymlinkUnknown = JBRootPathComparison(
            returnedRaw: "/a", confirmedRaw: "/a",
            returnedNormalized: "/a", confirmedNormalized: "/a",
            returnedSymlinkResolved: nil, confirmedSymlinkResolved: nil,
            rawMatch: true, normalizedMatch: true, symlinkMatch: nil, accessibleMatch: nil
        )
        XCTAssertEqual(JBRootPathComparator.verdict(normalizedMatchSymlinkUnknown), .passed)

        let noPaths = JBRootPathComparison(
            returnedRaw: nil, confirmedRaw: nil,
            returnedNormalized: nil, confirmedNormalized: nil,
            returnedSymlinkResolved: nil, confirmedSymlinkResolved: nil,
            rawMatch: nil, normalizedMatch: nil, symlinkMatch: nil, accessibleMatch: nil
        )
        XCTAssertEqual(JBRootPathComparator.verdict(noPaths), .unknown)
    }

    // MARK: - D7 统一服务异常隔离

    func testServiceContinuesAfterThrowingProbeAndPreservesIdentity() {
        let okChecker = FakeFileAccess(
            inspectResult: FileAccessResult(exists: true, isDirectory: true),
            entries: [URL(fileURLWithPath: "/a.dylib")]
        )
        let ok = JBRootProbe(confirmedJBRoot: "/private/var/jb", fileAccess: okChecker)
        let throwing = ThrowingProbe(probeID: "throwing.probe")
        let service = PermissionProbeService(probes: [throwing, ok])

        let report = service.runProbes()
        XCTAssertEqual(report.totalCount, 3)

        let failure = report.evidence.first { $0.probeID == "throwing.probe" }
        XCTAssertEqual(failure?.status, .failed)
        XCTAssertEqual(failure?.errorDomain, "test-probe")
        XCTAssertEqual(failure?.errorCode, 99)

        let okEvidence = report.evidence.filter { $0.probeID.hasPrefix("jbroot") }
        XCTAssertFalse(okEvidence.isEmpty)
    }

    func testServiceReportBuilderWritesGeneratedAt() {
        let service = PermissionProbeService(probes: [])
        let report = service.runProbes()
        XCTAssertNotNil(report.generatedAt)
        XCTAssertEqual(report.totalCount, 0)
    }
}
