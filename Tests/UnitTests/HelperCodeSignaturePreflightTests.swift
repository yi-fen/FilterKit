import XCTest
@testable import FilterKit

final class HelperCodeSignaturePreflightTests: XCTestCase {
    private func manifest(helperPins: [String]) -> HelperDeploymentManifest {
        HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide", jbRootPath: "/var/jb",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit", socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock",
            appCDHashes: [String(repeating: "a", count: 40)], helperCDHashes: helperPins,
            allowedClientUIDs: [501], stagingOwnerUID: 501)
    }

    func testRunningHelperCDHashMustMatchPinnedIdentity() throws {
        let pin = String(repeating: "b", count: 40)
        XCTAssertNoThrow(try HelperCodeSignatureVerifier().verifyRunningHelper(cdHash: pin, allowedCDHashes: [pin]))
        XCTAssertThrowsError(try HelperCodeSignatureVerifier().verifyRunningHelper(
            cdHash: String(repeating: "c", count: 40), allowedCDHashes: [pin]))
    }

    func testMalformedOrEmptyPinsFailClosed() {
        XCTAssertThrowsError(try HelperCodeSignatureVerifier().verifyRunningHelper(
            cdHash: String(repeating: "b", count: 40), allowedCDHashes: []))
        XCTAssertThrowsError(try HelperCodeSignatureVerifier().verifyRunningHelper(
            cdHash: "not-a-cdhash", allowedCDHashes: [String(repeating: "b", count: 40)]))
    }

    func testPreflightReportsPendingRecoveryWithoutMutating() throws {
        let directory = NSTemporaryDirectory() + "filterkit-p140-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let pin = String(repeating: "b", count: 40)
        let result = try HelperRuntimePreflight().inspect(runningCDHash: pin,
            manifest: manifest(helperPins: [pin]), pluginDirectory: directory)
        XCTAssertTrue(result.helperIdentityVerified)
        XCTAssertEqual(result.recoveryDetail, .clean)
        XCTAssertTrue(result.permitsNormalDeployment)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory), [])
    }

    func testStaticVerificationFailsClosedWhenPlatformDoesNotSupportIt() {
        #if !os(macOS)
        XCTAssertThrowsError(try HelperCodeSignatureVerifier().verifyStaticExecutable(
            at: "/tmp/filterkit-helper", expectedCDHash: String(repeating: "b", count: 40)))
        #endif
    }
}
