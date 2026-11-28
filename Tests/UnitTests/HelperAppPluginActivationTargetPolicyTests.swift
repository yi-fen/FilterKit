import XCTest
@testable import FilterKit

final class HelperAppPluginActivationTargetPolicyTests: XCTestCase {
    private let owner = "com.example.owner"

    func testFixedOwnerCanBeActivatedCaseInsensitively() throws {
        let result = try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: "COM.EXAMPLE.OWNER",
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [])
        XCTAssertEqual(result, .fixedOwner)
    }

    func testExistingAdditionalAssociationCanBeActivatedCaseInsensitively() throws {
        let result = try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: "COM.EXAMPLE.ALPHA",
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: false),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.beta", isEnabled: true)
            ])
        XCTAssertEqual(result, .additionalAssociation)
    }

    func testAPPActivationCannotCreateUnassociatedAppBinding() {
        XCTAssertThrowsError(try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: "com.example.newapp",
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: true)
            ])) { error in
                XCTAssertEqual(error as? HelperAppPluginActivationTargetPolicy.PolicyError, .notAssociated)
            }
    }

    func testDuplicateCaseVariantAssociationsFailClosed() {
        XCTAssertThrowsError(try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: "com.example.alpha",
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "COM.EXAMPLE.ALPHA", isEnabled: false)
            ])) { error in
                XCTAssertEqual(error as? HelperAppPluginActivationTargetPolicy.PolicyError, .duplicateAssociation)
            }
    }

    func testFixedOwnerCannotAlsoAppearAsAdditionalAssociation() {
        XCTAssertThrowsError(try HelperAppPluginActivationTargetPolicy.validate(
            targetBundleIdentifier: "com.example.alpha",
            fixedOwnerBundleIdentifier: owner,
            additionalAssociations: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "COM.EXAMPLE.OWNER", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: true)
            ])) { error in
                XCTAssertEqual(error as? HelperAppPluginActivationTargetPolicy.PolicyError, .duplicateAssociation)
            }
    }
}
