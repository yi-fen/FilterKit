import XCTest
@testable import FilterKit

final class PluginBindingTopologyTests: XCTestCase {
    private let editor = PluginBindingTopologyEditor()

    func testFirstSuccessfulBatchCreatesEnabledFixedOwner() {
        let decision = PluginImportBatchDecision(id: UUID(), targetBundleIdentifier: "com.example.owner",
            bindingMode: .fixedOwner, defaultsEnabled: true, isFirstSuccessfulBatch: true)
        let topology = PluginBindingTopology.forImport(pluginID: UUID(), decision: decision)
        XCTAssertEqual(topology.bindingKind, .fixedOwner)
        XCTAssertEqual(topology.fixedOwnerBundleIdentifier, "com.example.owner")
        XCTAssertTrue(topology.fixedOwnerIsEnabled)
        XCTAssertTrue(topology.additionalAssociations.isEmpty)
    }

    func testLaterBatchCreatesEnabledAssociationOnly() {
        let decision = PluginImportBatchDecision(id: UUID(), targetBundleIdentifier: "com.example.target",
            bindingMode: .additionalAssociation, defaultsEnabled: true, isFirstSuccessfulBatch: false)
        let topology = PluginBindingTopology.forImport(pluginID: UUID(), decision: decision)
        XCTAssertEqual(topology.bindingKind, .additionalAssociationsOnly)
        XCTAssertNil(topology.fixedOwnerBundleIdentifier)
        XCTAssertEqual(topology.additionalAssociations, [PluginBindingAssociation(bundleIdentifier: "com.example.target", isEnabled: true)])
    }

    func testFixedOwnerCanBeDisabledButCannotBeRemoved() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: "com.example.owner")
        let disabled = try editor.setFixedOwnerEnabled(false, in: topology)
        XCTAssertFalse(disabled.fixedOwnerIsEnabled)
        XCTAssertTrue(disabled.enabledBundleIdentifiers.isEmpty)
        XCTAssertThrowsError(try editor.addAdditionalAssociation("com.example.owner", to: topology))
    }

    func testFixedOwnerActivationChangesWithoutChangingIdentityOrSoftStates() throws {
        let pluginID = UUID()
        let topology = PluginBindingTopology(pluginID: pluginID, fixedOwnerBundleIdentifier: "com.example.owner",
            additionalAssociations: [PluginBindingAssociation(bundleIdentifier: "com.example.extra", isEnabled: true)])
        let disabled = try editor.setFixedOwnerEnabled(false, in: topology)
        XCTAssertEqual(disabled.pluginID, pluginID)
        XCTAssertEqual(disabled.fixedOwnerBundleIdentifier, "com.example.owner")
        XCTAssertFalse(disabled.fixedOwnerIsEnabled)
        XCTAssertEqual(disabled.additionalAssociations, topology.additionalAssociations)
        XCTAssertEqual(disabled.enabledBundleIdentifiers, ["com.example.extra"])
    }

    func testActiveAdditionalAssociationCanBeRemovedByPluginPage() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: nil,
            additionalAssociations: [PluginBindingAssociation(bundleIdentifier: "com.example.target", isEnabled: true)])
        let removed = try editor.removeAdditionalAssociation("com.example.target", from: topology)
        XCTAssertTrue(removed.additionalAssociations.isEmpty)
    }

    func testPluginPageAdditionDefaultsDisabled() throws {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: "com.example.owner")
        let updated = try editor.addAdditionalAssociation("com.example.other", to: topology)
        XCTAssertEqual(updated.additionalAssociations.first?.isEnabled, false)
    }

    func testValidatorRejectsDuplicateAndOwnerAsAdditionalAssociation() {
        let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: "com.example.owner",
            additionalAssociations: [
                PluginBindingAssociation(bundleIdentifier: "com.example.owner", isEnabled: false),
                PluginBindingAssociation(bundleIdentifier: "com.example.other", isEnabled: false),
                PluginBindingAssociation(bundleIdentifier: "com.example.other", isEnabled: true)
            ])
        XCTAssertFalse(PluginBindingTopologyValidator().validate(topology).isEmpty)
    }
}
