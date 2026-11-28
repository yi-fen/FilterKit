import XCTest
@testable import FilterKit

final class HelperInstallerRecoveryPreflightTests: XCTestCase {
    func testLayoutUsesCanonicalActivePathsAndThreeArtifactSets() throws {
        let layout = try HelperInstallerRecoveryLayout(
            stagedRootRelativePath: "Library/FilterKit/Helper/Recovery/tx-a/staged",
            previousRootRelativePath: "Library/FilterKit/Helper/Recovery/tx-a/previous")
        XCTAssertEqual(layout.activePaths[.executable], HelperRootReleaseSet.executablePath)
        XCTAssertEqual(layout.stagedPaths.count, HelperRootReleaseSet.Artifact.allCases.count)
        XCTAssertEqual(layout.previousPaths?.count, HelperRootReleaseSet.Artifact.allCases.count)
    }

    func testLayoutRejectsTraversalAndOverlappingRoots() {
        XCTAssertThrowsError(try HelperInstallerRecoveryLayout(
            stagedRootRelativePath: "../../tmp/staged", previousRootRelativePath: nil))
        XCTAssertThrowsError(try HelperInstallerRecoveryLayout(
            stagedRootRelativePath: "Library/FilterKit/Helper/Recovery/tx/staged",
            previousRootRelativePath: "Library/FilterKit/Helper/Recovery/tx/staged/child"))
    }

    func testServiceObservationBindsObserverAndExecutableIdentity() {
        let observer = String(repeating: "a", count: 64)
        let executable = String(repeating: "b", count: 64)
        let observation = HelperInstallerServiceObservation(
            launchDaemonLabel: "cn.yfen.filterkit.helper",
            observerCodeIdentitySHA256: observer,
            state: .running(pid: 123, executableSHA256: executable))
        XCTAssertTrue(observation.validates(expectedObserverCodeIdentitySHA256: observer,
                                            expectedExecutableSHA256: executable))
        XCTAssertFalse(observation.validates(expectedObserverCodeIdentitySHA256: String(repeating: "c", count: 64),
                                             expectedExecutableSHA256: executable))
    }

    func testEvidenceEqualityDetectsJournalAndServiceChanges() {
        let hash = String(repeating: "a", count: 64)
        let first = HelperInstallerRecoveryPreflight.Evidence(journalSequence: 1,
            journalHeadHash: hash, activeRecords: [:], stagedRecords: [:], previousRecords: [:], activePointer: nil,
            activePointerMatchesObservedArtifacts: false, ownershipVerified: true,
            serviceLabel: "cn.yfen.filterkit.helper", serviceObserverCodeIdentitySHA256: hash, serviceState: .stopped)
        let changed = HelperInstallerRecoveryPreflight.Evidence(journalSequence: 2,
            journalHeadHash: hash, activeRecords: [:], stagedRecords: [:], previousRecords: [:], activePointer: nil,
            activePointerMatchesObservedArtifacts: false, ownershipVerified: true,
            serviceLabel: "cn.yfen.filterkit.helper", serviceObserverCodeIdentitySHA256: hash, serviceState: .stopped)
        XCTAssertNotEqual(first, changed)
    }
}
