import XCTest
@testable import FilterKit

final class PluginFirstInstallBindingPolicyTests: XCTestCase {
    private let owner = "com.example.owner"
    private let alpha = "com.example.alpha"
    private let beta = "com.example.beta"

    func testFirstInjectionCreatesSchemaFourFixedOwnerAndPreservesIndependentStates() throws {
        let associations = [
            FilterKitManifestSoftAssociation(bundleIdentifier: alpha, isEnabled: true),
            FilterKitManifestSoftAssociation(bundleIdentifier: beta, isEnabled: false)
        ]
        let manifest = try PluginFirstInstallBindingPolicy.makeManifest(
            pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64),
            machOIdentitySHA256: String(repeating: "c", count: 64),
            fixedOwnerBundleIdentifier: owner, additionalAssociations: associations,
            filterPlistData: makeFilter([owner, alpha]))

        XCTAssertEqual(manifest.schemaVersion, 4)
        XCTAssertEqual(manifest.hardBoundBundleIdentifier, owner)
        XCTAssertEqual(manifest.bindingTopology?.fixedOwnerBundleIdentifier, owner)
        XCTAssertEqual(manifest.bindingTopology?.fixedOwnerIsEnabled, true)
        XCTAssertEqual(manifest.bindingTopology?.additionalAssociations, associations)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest, targetBundleIdentifier: owner), true)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest, targetBundleIdentifier: alpha), true)
        XCTAssertEqual(HelperAppPluginActivationStateReader.enabledState(in: manifest, targetBundleIdentifier: beta), false)
    }

    func testFirstInjectionRejectsFilterMissingFixedOwner() {
        XCTAssertThrowsError(try PluginFirstInstallBindingPolicy.makeManifest(
            pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64),
            machOIdentitySHA256: String(repeating: "c", count: 64),
            fixedOwnerBundleIdentifier: owner, additionalAssociations: [],
            filterPlistData: makeFilter([alpha])))
    }

    func testFirstInjectionRejectsEnabledStateAndFilterMismatch() {
        let associations = [FilterKitManifestSoftAssociation(bundleIdentifier: alpha, isEnabled: true)]
        XCTAssertThrowsError(try PluginFirstInstallBindingPolicy.makeManifest(
            pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64),
            machOIdentitySHA256: String(repeating: "c", count: 64),
            fixedOwnerBundleIdentifier: owner, additionalAssociations: associations,
            filterPlistData: makeFilter([owner])))
    }

    func testCaseVariantDuplicateAssociationIsRejected() {
        let associations = [
            FilterKitManifestSoftAssociation(bundleIdentifier: alpha, isEnabled: true),
            FilterKitManifestSoftAssociation(bundleIdentifier: "COM.EXAMPLE.ALPHA", isEnabled: false)
        ]
        XCTAssertThrowsError(try PluginFirstInstallBindingPolicy.makeManifest(
            pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64),
            machOIdentitySHA256: String(repeating: "c", count: 64),
            fixedOwnerBundleIdentifier: owner, additionalAssociations: associations,
            filterPlistData: makeFilter([owner, alpha])))
    }

    func testFixedOwnerCannotBeRepeatedAsAdditionalAssociationWithDifferentCase() {
        XCTAssertThrowsError(try PluginFirstInstallBindingPolicy.makeManifest(
            pluginID: UUID(), dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64),
            machOIdentitySHA256: String(repeating: "c", count: 64),
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [.init(bundleIdentifier: "COM.EXAMPLE.OWNER", isEnabled: true)],
            filterPlistData: makeFilter([owner])))
    }

    private func makeFilter(_ bundles: [String]) -> Data {
        (try? PropertyListSerialization.data(fromPropertyList: ["Filter": [
            "Bundles": bundles, "Executables": [String](), "Classes": [String]()
        ]], format: .xml, options: 0)) ?? Data()
    }
}
