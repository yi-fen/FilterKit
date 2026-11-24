import XCTest
@testable import FilterKit

final class EnvironmentProbeModelTests: XCTestCase {
    func testProbeStatusesAreCodable() throws {
        let result = PathProbeResult(id: "root-test", path: "/var/jb", status: .missing,
                                     isDirectory: false, detailCode: "path.not_found")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PathProbeResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testDiagnosticReportDeclaresReadOnly() {
        let report = EnvironmentDiagnosticReport(
            detectedAt: Date(),
            environment: JailbreakEnvironment(kind: .unknown, displayVersion: nil,
                elleKit: ElleKitInstallation(version: nil, commit: nil, isPresent: false)),
            rootCandidates: [], rootValidation: JBRootValidationReport(validatedAt: Date(), candidates: [],
                validatedRootPath: nil, environmentKind: .unknown, warnings: [], isReadOnly: true, apiEvidence: nil),
            dynamicLibrariesCandidates: [], elleKitCandidates: [],
            resolvedRootPath: nil, resolvedDynamicLibrariesPath: nil,
            warnings: ["environment.probe.read_only"], isReadOnly: true)
        XCTAssertTrue(report.isReadOnly)
        XCTAssertNil(report.resolvedRootPath)
    }
}
