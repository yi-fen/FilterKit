import XCTest
@testable import FilterKit

final class ElleKitProfileMatcherTests: XCTestCase {
    private func package(version: String = "1.2-3", architecture: String? = "iphoneos-arm64e",
                         maintainer: String? = nil, origin: String? = nil,
                         homepage: String? = nil) -> ElleKitPackageMetadata {
        ElleKitPackageMetadata(package: "ellekit", version: version, architecture: architecture,
                               status: "install ok installed", maintainer: maintainer,
                               origin: origin, homepage: homepage, sourcePath: "/fixture/status",
                               isCurrentStatusDatabase: true)
    }

    private func pinnedRegistry() throws -> ElleKitProfileRegistry {
        let record = ElleKitProfileRecord(
            id: "fixture-profile", environment: "rootHide", status: "verified",
            allowedPackageVersions: ["1.2-3"],
            packageIdentity: .init(package: "ellekit", architectures: ["iphoneos-arm64e"],
                                   maintainers: ["Fixture Maintainer"], origins: ["Fixture Origin"],
                                   homepages: ["https://fixture.invalid"]),
            binaryFingerprints: [
                .init(installName: "/usr/lib/libellekit.dylib",
                      uuid: "00112233445566778899aabbccddeeff",
                      cdHash: "aabbccdd", architectures: ["arm64e"])
            ], note: "Test-only fixture")
        return try ElleKitProfileRegistry(profiles: [record])
    }

    func testReferenceProfileNeverClaimsBinaryMatchFromVersionAlone() {
        let result = ElleKitProfileMatcher().match(environment: .rootHide,
                                                   package: package(), fingerprints: [])
        XCTAssertEqual(result.outcome, .unknownFingerprint)
        XCTAssertEqual(result.profileIdentifier, "roothide-dopamine-ellekit-1.2-3-16e3e7e")
    }

    func testVersionMismatchIsSeparateFromIdentityMismatch() {
        let result = ElleKitProfileMatcher().match(environment: .rootHide,
                                                   package: package(version: "1.2-4"), fingerprints: [])
        XCTAssertEqual(result.outcome, .versionMismatch)
    }

    func testPackageArchitectureConflictIsIdentityMismatch() {
        let result = ElleKitProfileMatcher().match(environment: .rootHide,
                                                   package: package(architecture: "iphoneos-arm"), fingerprints: [])
        XCTAssertEqual(result.outcome, .identityMismatch)
    }

    func testMissingPinnedPackageIdentityFieldIsUnverifiable() {
        let result = ElleKitProfileMatcher().match(environment: .rootHide,
                                                   package: package(architecture: nil), fingerprints: [])
        XCTAssertEqual(result.outcome, .unverifiable)
    }

    func testMissingPackageEvidenceIsUnverifiable() {
        let result = ElleKitProfileMatcher().match(environment: .rootHide,
                                                   package: nil, fingerprints: [], hasInaccessibleEvidence: true)
        XCTAssertEqual(result.outcome, .unverifiable)
    }

    func testAllPinnedIdentityFieldsMustMatch() throws {
        let matcher = ElleKitProfileMatcher(registry: try pinnedRegistry())
        let matching = ElleKitBinaryFingerprint(installName: "/usr/lib/libellekit.dylib",
                                                currentVersion: "1.0.2", compatibilityVersion: "1.0.0",
                                                uuid: "00112233445566778899aabbccddeeff",
                                                cdHash: "AABBCCDD", architecture: "arm64e")
        let result = matcher.match(environment: .rootHide,
                                   package: package(maintainer: "Fixture Maintainer",
                                                    origin: "Fixture Origin",
                                                    homepage: "https://fixture.invalid"),
                                   fingerprints: [matching])
        XCTAssertEqual(result.outcome, .matched)
        XCTAssertEqual(result.profileIdentifier, "fixture-profile")
        // A binary identity match is not proof of the source-control commit.
    }

    func testBinaryFingerprintConflictIsIdentityMismatch() throws {
        let matcher = ElleKitProfileMatcher(registry: try pinnedRegistry())
        let conflicting = ElleKitBinaryFingerprint(installName: "/usr/lib/libellekit.dylib",
                                                   currentVersion: "1.0.2", compatibilityVersion: "1.0.0",
                                                   uuid: "00112233445566778899aabbccddeeff",
                                                   cdHash: "deadbeef", architecture: "arm64e")
        let result = matcher.match(environment: .rootHide,
                                   package: package(maintainer: "Fixture Maintainer",
                                                    origin: "Fixture Origin",
                                                    homepage: "https://fixture.invalid"),
                                   fingerprints: [conflicting])
        XCTAssertEqual(result.outcome, .identityMismatch)
    }

    func testPinnedProfileWithMissingCDHashIsUnverifiable() throws {
        let matcher = ElleKitProfileMatcher(registry: try pinnedRegistry())
        let incomplete = ElleKitBinaryFingerprint(installName: "/usr/lib/libellekit.dylib",
                                                  currentVersion: "1.0.2", compatibilityVersion: "1.0.0",
                                                  uuid: "00112233445566778899aabbccddeeff",
                                                  cdHash: nil, architecture: "arm64e")
        let result = matcher.match(environment: .rootHide,
                                   package: package(maintainer: "Fixture Maintainer",
                                                    origin: "Fixture Origin",
                                                    homepage: "https://fixture.invalid"),
                                   fingerprints: [incomplete])
        XCTAssertEqual(result.outcome, .unverifiable)
    }

    func testRegistryDecodesVersionedProfileDocument() throws {
        let json = """
        {"schemaVersion":2,"profiles":[{"id":"json-profile","environment":"rootHide","status":"reference-baseline","allowedPackageVersions":["1.2-3"],"packageIdentity":{"package":"ellekit","architectures":["iphoneos-arm64e"],"maintainers":[],"origins":[],"homepages":[]},"binaryFingerprints":[],"note":"fixture"}]}
        """
        let registry = try ElleKitProfileRegistry(jsonData: Data(json.utf8))
        XCTAssertEqual(registry.profiles.map(\.id), ["json-profile"])
    }

    func testRegistryRejectsUnsupportedSchemaVersion() {
        let json = Data("{\"schemaVersion\":1,\"profiles\":[]}".utf8)
        XCTAssertThrowsError(try ElleKitProfileRegistry(jsonData: json))
    }

    func testRegistryRejectsDuplicateIdentifiers() {
        let record = ElleKitProfileRecord(id: "duplicate", environment: "rootHide", status: "reference",
                                          allowedPackageVersions: [], packageIdentity: .init(),
                                          binaryFingerprints: [], note: nil)
        XCTAssertThrowsError(try ElleKitProfileRegistry(profiles: [record, record]))
    }

    func testMultipleProfilesMatchingSameBinaryAreAmbiguous() throws {
        let base = try pinnedRegistry().profiles[0]
        let duplicate = ElleKitProfileRecord(
            id: "fixture-profile-duplicate", environment: base.environment, status: base.status,
            allowedPackageVersions: base.allowedPackageVersions,
            packageIdentity: base.packageIdentity,
            binaryFingerprints: base.binaryFingerprints, note: "second overlapping profile")
        let registry = try ElleKitProfileRegistry(profiles: [base, duplicate])
        let actual = ElleKitBinaryFingerprint(installName: "/usr/lib/libellekit.dylib",
                                              currentVersion: "1.0.2", compatibilityVersion: "1.0.0",
                                              uuid: "00112233445566778899aabbccddeeff",
                                              cdHash: "aabbccdd", architecture: "arm64e")
        let result = ElleKitProfileMatcher(registry: registry).match(
            environment: .rootHide,
            package: package(maintainer: "Fixture Maintainer", origin: "Fixture Origin",
                             homepage: "https://fixture.invalid"),
            fingerprints: [actual])
        XCTAssertEqual(result.outcome, .ambiguous)
        XCTAssertNil(result.profileIdentifier)
    }

    func testMatchingAndConflictingBinaryCandidatesAreAmbiguous() throws {
        let matcher = ElleKitProfileMatcher(registry: try pinnedRegistry())
        let matching = ElleKitBinaryFingerprint(installName: "/usr/lib/libellekit.dylib",
                                                currentVersion: "1.0.2", compatibilityVersion: "1.0.0",
                                                uuid: "00112233445566778899aabbccddeeff",
                                                cdHash: "aabbccdd", architecture: "arm64e")
        let conflicting = ElleKitBinaryFingerprint(installName: "/usr/lib/libellekit.dylib",
                                                   currentVersion: "1.0.2", compatibilityVersion: "1.0.0",
                                                   uuid: "ffffffffffffffffffffffffffffffff",
                                                   cdHash: "deadbeef", architecture: "arm64e")
        let result = matcher.match(environment: .rootHide,
                                   package: package(maintainer: "Fixture Maintainer",
                                                    origin: "Fixture Origin",
                                                    homepage: "https://fixture.invalid"),
                                   fingerprints: [matching, conflicting])
        XCTAssertEqual(result.outcome, .ambiguous)
    }

}
