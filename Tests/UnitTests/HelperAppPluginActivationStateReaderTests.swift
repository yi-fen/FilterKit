import XCTest
@testable import FilterKit

final class HelperAppPluginActivationStateReaderTests: XCTestCase {
    private let owner = "com.example.owner"
    private let alpha = "com.example.alpha"
    private let beta = "com.example.beta"

    func testSchemaThreeFixedOwnerIsEnabledByLegacyContract() {
        let manifest = makeManifest(schema: 3, ownerEnabled: true,
            associations: [.init(bundleIdentifier: alpha, isEnabled: false)])
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: owner), true)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: alpha), false)
    }

    func testSchemaFourReadsFixedOwnerBitAndIndependentAssociationBits() {
        let manifest = makeManifest(schema: 4, ownerEnabled: false,
            associations: [.init(bundleIdentifier: alpha, isEnabled: true),
                           .init(bundleIdentifier: beta, isEnabled: false)])
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: owner), false)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: alpha), true)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: beta), false)
    }

    func testUnknownAssociationDoesNotDefaultToDisabled() {
        let manifest = makeManifest(schema: 4, ownerEnabled: true,
            associations: [.init(bundleIdentifier: alpha, isEnabled: true)])
        XCTAssertNil(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: "com.example.unknown"))
        XCTAssertNil(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: ""))
    }

    func testDuplicateAssociationMetadataFailsClosed() {
        let duplicate = makeManifest(schema: 4, ownerEnabled: true,
            associations: [.init(bundleIdentifier: alpha, isEnabled: true),
                           .init(bundleIdentifier: alpha, isEnabled: false)])
        XCTAssertNil(HelperAppPluginActivationStateReader.enabledState(in: duplicate,
            targetBundleIdentifier: owner))
    }

    func testInconsistentSchemaFourMirrorFailsClosed() {
        let valid = makeManifest(schema: 4, ownerEnabled: true,
            associations: [.init(bundleIdentifier: alpha, isEnabled: true)])
        let inconsistent = FilterKitPluginManifest(schemaVersion: 4, pluginID: valid.pluginID,
            dylibFileName: valid.dylibFileName, plistFileName: valid.plistFileName,
            dylibSHA256: valid.dylibSHA256, plistSHA256: valid.plistSHA256,
            hardBoundBundleIdentifier: owner,
            softAssociatedBundleIdentifiers: [alpha, beta],
            machOIdentitySHA256: valid.machOIdentitySHA256,
            softAssociations: valid.softAssociations,
            bindingTopology: valid.bindingTopology)
        XCTAssertNil(HelperAppPluginActivationStateReader.enabledState(in: inconsistent,
            targetBundleIdentifier: owner))
    }


    func testBundleIdentifierMatchingIsCaseInsensitiveAcrossManifestMirrors() {
        let mixedCaseAssociation = FilterKitManifestSoftAssociation(bundleIdentifier: "Com.Example.Alpha", isEnabled: true)
        let manifest = FilterKitPluginManifest(schemaVersion: 4, pluginID: UUID().uuidString,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
            hardBoundBundleIdentifier: "Com.Example.Owner",
            softAssociatedBundleIdentifiers: ["com.example.alpha"],
            machOIdentitySHA256: String(repeating: "c", count: 64),
            softAssociations: [mixedCaseAssociation],
            bindingTopology: FilterKitManifestBindingTopology(schemaVersion: 1,
                fixedOwnerBundleIdentifier: "com.example.owner", fixedOwnerIsEnabled: false,
                additionalAssociations: [mixedCaseAssociation]))

        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: "COM.EXAMPLE.OWNER"), false)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: "com.example.alpha"), true)
    }

    func testCaseVariantDuplicateAssociationsFailClosed() {
        let manifest = makeManifest(schema: 4, ownerEnabled: true,
            associations: [.init(bundleIdentifier: alpha, isEnabled: true),
                           .init(bundleIdentifier: "COM.EXAMPLE.ALPHA", isEnabled: false)])
        XCTAssertNil(HelperAppPluginActivationStateReader.enabledState(in: manifest,
            targetBundleIdentifier: owner))
    }

    private func makeManifest(schema: Int, ownerEnabled: Bool,
                              associations: [FilterKitManifestSoftAssociation]) -> FilterKitPluginManifest {
        let topology = schema == 4
            ? FilterKitManifestBindingTopology(schemaVersion: 1,
                fixedOwnerBundleIdentifier: owner, fixedOwnerIsEnabled: ownerEnabled,
                additionalAssociations: associations)
            : nil
        return FilterKitPluginManifest(schemaVersion: schema, pluginID: UUID().uuidString,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64),
            hardBoundBundleIdentifier: owner,
            softAssociatedBundleIdentifiers: associations.map(\.bundleIdentifier),
            machOIdentitySHA256: String(repeating: "c", count: 64),
            softAssociations: associations, bindingTopology: topology)
    }
}
