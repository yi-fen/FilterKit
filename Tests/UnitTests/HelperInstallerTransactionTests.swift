import XCTest
@testable import FilterKit

final class HelperInstallerTransactionTests: XCTestCase {
    private func bundle() throws -> HelperInstallerProvisioningBundle {
        let value = HelperInstallerProvisioningBundle(schemaVersion: 2, generation: 10,
            releaseIdentifier: "1.0.0-p135", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "a", count: 40),
            helperCDHash: String(repeating: "b", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "dopamine-roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
        try value.validate()
        return value
    }

    func testReleaseVerifierChecksExactBytesAndDisabledLaunchDaemon() throws {
        let bundle = try bundle()
        let executable = Data([0xcf, 0xfa, 0xed, 0xfe, 0x01, 0x02])
        let launch = try bundle.disabledLaunchDaemonPlist()
        let digests = [
            HelperInstallerArtifactDigest(relativePath: "usr/libexec/filterkit-helper", sha256: SHA256Digest.hex(executable)),
            HelperInstallerArtifactDigest(relativePath: "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist", sha256: SHA256Digest.hex(launch))
        ]
        let result = try HelperInstallerReleaseVerifier().verify(bundle: bundle,
            artifacts: ["usr/libexec/filterkit-helper": executable,
                        "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist": launch],
            expectedDigests: digests)
        XCTAssertEqual(result.releaseIdentifier, bundle.releaseIdentifier)
        XCTAssertEqual(result.executableSHA256, SHA256Digest.hex(executable))

        let altered = Data([0xcf, 0xfa, 0xed, 0xfe, 0x09])
        XCTAssertThrowsError(try HelperInstallerReleaseVerifier().verify(bundle: bundle,
            artifacts: ["usr/libexec/filterkit-helper": altered,
                        "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist": launch],
            expectedDigests: digests))
    }

    func testJournalEnforcesOrderedUpgradeAndRollback() throws {
        var journal = try HelperInstallerTransactionJournal(action: .upgrade,
            releaseIdentifier: "1.0.0-p135", generation: 10)
        try journal.apply(.verifyArtifacts)
        try journal.apply(.preservePreviousRelease)
        try journal.apply(.stageRelease)
        try journal.apply(.activateRelease)
        try journal.apply(.beginRollback)
        try journal.apply(.completeRollback)
        try journal.validateChain()
        XCTAssertEqual(journal.state, .rolledBack)
        XCTAssertEqual(journal.sequence, 6)
    }

    func testJournalRejectsOutOfOrderActivation() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p135", generation: 10)
        XCTAssertThrowsError(try journal.apply(.activateRelease))
    }

    func testJournalDetectsTamperedEventHash() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p135", generation: 10)
        try journal.apply(.verifyArtifacts)
        var encoded = try JSONEncoder().encode(journal)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0]["hash"] = String(repeating: "f", count: 64)
        object["entries"] = entries
        encoded = try JSONSerialization.data(withJSONObject: object)
        let tampered = try JSONDecoder().decode(HelperInstallerTransactionJournal.self, from: encoded)
        XCTAssertThrowsError(try tampered.validateChain())
    }

    func testExecutionGateAlwaysBlocksUnreleasedPlan() throws {
        let bundle = try bundle()
        let plan = try HelperInstallerTransactionPlan.make(action: .install, bundle: bundle)
        let reason = HelperInstallerExecutionGate().blockReason(plan: plan,
            evidence: .init(rootInstallerAvailable: true, releaseProvenanceVerified: true,
                            signedArtifactsVerified: true, operatorApproved: true))
        XCTAssertEqual(reason, .planNotReleased)
        XCTAssertFalse(plan.executionEnabled)
    }
}
