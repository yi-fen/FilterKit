import XCTest
@testable import FilterKit

final class PluginAssociationPlanTests: XCTestCase {
    func testAssociationEditorHasNoPerAppActivationEditAndPreservesExistingBits() throws {
        let active = PluginSoftAssociation(bundleIdentifier: "com.example.active", isEnabled: true)
        let inactive = PluginSoftAssociation(bundleIdentifier: "com.example.inactive", isEnabled: false)
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [active, inactive])
        let editor = PluginAssociationPlanEditor()
        let added = try editor.applying(.addSoft(bundleIdentifier: "com.example.new"), to: plan,
            installedBundleIdentifiers: ["com.example.active", "com.example.inactive", "com.example.new"],
            pluginIsManageable: true).get()
        XCTAssertEqual(added.softAssociations.first(where: { $0.bundleIdentifier == active.bundleIdentifier })?.isEnabled, true)
        XCTAssertEqual(added.softAssociations.first(where: { $0.bundleIdentifier == inactive.bundleIdentifier })?.isEnabled, false)
        XCTAssertEqual(added.softAssociations.first(where: { $0.bundleIdentifier == "com.example.new" })?.isEnabled, false)
    }

    func testDisabledSoftAssociationIsNotEffectiveButRemainsInPlan() {
        let plan = PluginAssociationPlan(
            pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [
                PluginSoftAssociation(bundleIdentifier: "com.example.enabled", isEnabled: true),
                PluginSoftAssociation(bundleIdentifier: "com.example.disabled", isEnabled: false),
                PluginSoftAssociation(bundleIdentifier: "com.example.missing", isEnabled: true)
            ]
        )
        let resolution = PluginAssociationPlanResolver().resolve(plan, installedBundleIdentifiers: [
            "com.example.source", "com.example.enabled", "com.example.disabled"
        ])
        XCTAssertEqual(resolution.effectiveBundleIdentifiers, ["com.example.enabled", "com.example.source"])
        XCTAssertEqual(resolution.disabledSoftBundleIdentifiers, ["com.example.disabled"])
        XCTAssertEqual(resolution.missingSoftBundleIdentifiers, ["com.example.missing"])
    }

    func testMissingHardBoundIdentityIsPreservedAndNotMigrated() {
        let plan = PluginAssociationPlan(
            pluginID: UUID(), hardBoundBundleIdentifier: "com.example.original",
            softAssociations: [PluginSoftAssociation(bundleIdentifier: "com.example.available", isEnabled: true)]
        )
        let resolution = PluginAssociationPlanResolver().resolve(plan, installedBundleIdentifiers: ["com.example.available"])
        XCTAssertEqual(resolution.hardBoundBundleIdentifier, "com.example.original")
        XCTAssertFalse(resolution.hardBoundIsInstalled)
        XCTAssertEqual(resolution.effectiveBundleIdentifiers, ["com.example.available"])
    }

    func testOnlyFilterKitManageablePluginCanEditPlan() {
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source")
        let result = PluginAssociationPlanEditor().applying(.addSoft(bundleIdentifier: "com.example.other"),
            to: plan, installedBundleIdentifiers: ["com.example.other"], pluginIsManageable: false)
        XCTAssertEqual(try? result.get(), nil)
        if case .failure(let error) = result { XCTAssertEqual(error, .pluginNotManageable) }
        else { XCTFail("Expected authorization denial") }
    }

    func testAddingSoftAssociationDoesNotEnableInjection() throws {
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [PluginSoftAssociation(bundleIdentifier: "com.example.existing", isEnabled: false)])
        let added = try PluginAssociationPlanEditor().applying(.addSoft(bundleIdentifier: "com.example.new"), to: plan,
            installedBundleIdentifiers: ["com.example.existing", "com.example.new"], pluginIsManageable: true).get()
        XCTAssertEqual(added.softAssociations.first(where: { $0.bundleIdentifier == "com.example.existing" })?.isEnabled, false)
        XCTAssertEqual(added.softAssociations.first(where: { $0.bundleIdentifier == "com.example.new" })?.isEnabled, false)
    }

    func testRemoveAndReaddExistingAssociationPreservesActivationBit() throws {
        let active = PluginSoftAssociation(bundleIdentifier: "com.example.active", isEnabled: true)
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [active])
        let editor = PluginAssociationPlanEditor()
        let removed = try editor.applying(.removeSoft(bundleIdentifier: active.bundleIdentifier), to: plan,
            installedBundleIdentifiers: [active.bundleIdentifier], pluginIsManageable: true).get()
        let restored = try editor.applying(.restoreSoft(association: active), to: removed,
            installedBundleIdentifiers: [active.bundleIdentifier], pluginIsManageable: true).get()
        XCTAssertEqual(restored.softAssociations, [active])
    }

    func testDuplicateAndHardBoundSoftAssociationAreRejected() {
        var plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source")
        plan.softAssociations = [
            PluginSoftAssociation(bundleIdentifier: "com.example.source", isEnabled: true),
            PluginSoftAssociation(bundleIdentifier: "com.example.other", isEnabled: true),
            PluginSoftAssociation(bundleIdentifier: "com.example.other", isEnabled: false)
        ]
        let resolution = PluginAssociationPlanResolver().resolve(plan, installedBundleIdentifiers: [
            "com.example.source", "com.example.other"
        ])
        XCTAssertFalse(resolution.isValid)
        XCTAssertTrue(resolution.issues.contains(.hardBoundCannotBeSoftAssociated))
        XCTAssertTrue(resolution.issues.contains(.duplicateSoftAssociation))
        XCTAssertEqual(resolution.effectiveBundleIdentifiers, ["com.example.other", "com.example.source"])
    }

    func testBundleIdentifierIdentityIsCaseInsensitiveForResolutionAndDuplicateDetection() {
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [
                PluginSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: true),
                PluginSoftAssociation(bundleIdentifier: "COM.EXAMPLE.TARGET", isEnabled: false),
                PluginSoftAssociation(bundleIdentifier: "COM.EXAMPLE.SOURCE", isEnabled: true)
            ])
        let result = PluginAssociationPlanResolver().resolve(plan, installedBundleIdentifiers: [
            "COM.EXAMPLE.SOURCE", "COM.EXAMPLE.TARGET"
        ])
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains(.duplicateSoftAssociation))
        XCTAssertTrue(result.issues.contains(.hardBoundCannotBeSoftAssociated))
        XCTAssertTrue(result.hardBoundIsInstalled)
    }

    func testAssociationEditorUsesCanonicalBundleIdentity() throws {
        let editor = PluginAssociationPlanEditor()
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [PluginSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: true)])
        let installed: Set<String> = ["COM.EXAMPLE.SOURCE", "COM.EXAMPLE.TARGET"]
        let duplicate = editor.applying(.addSoft(bundleIdentifier: "COM.EXAMPLE.TARGET"), to: plan,
            installedBundleIdentifiers: installed, pluginIsManageable: true)
        if case .failure(let error) = duplicate { XCTAssertEqual(error, .duplicateAssociation) }
        else { XCTFail("Case-variant duplicate must be rejected") }

        let removed = try editor.applying(.removeSoft(bundleIdentifier: "COM.EXAMPLE.TARGET"), to: plan,
            installedBundleIdentifiers: installed, pluginIsManageable: true).get()
        XCTAssertTrue(removed.softAssociations.isEmpty)
    }

    func testSoftAssociationAddAndRemoveArePlanOnlyOperations() throws {
        let plan = PluginAssociationPlan(pluginID: UUID(), hardBoundBundleIdentifier: "com.example.source")
        let editor = PluginAssociationPlanEditor()
        let added = try editor.applying(.addSoft(bundleIdentifier: "com.example.other"), to: plan,
            installedBundleIdentifiers: ["com.example.other"], pluginIsManageable: true).get()
        XCTAssertEqual(added.softAssociations, [PluginSoftAssociation(bundleIdentifier: "com.example.other", isEnabled: false)])
        let removed = try editor.applying(.removeSoft(bundleIdentifier: "com.example.other"), to: added,
            installedBundleIdentifiers: ["com.example.other"], pluginIsManageable: true).get()
        XCTAssertTrue(removed.softAssociations.isEmpty)
        XCTAssertEqual(removed.hardBoundBundleIdentifier, "com.example.source")
    }
}
