import XCTest
@testable import FilterKit

final class PluginImportBatchPolicyTests: XCTestCase {
    func testFirstSuccessfulBatchUsesFixedOwnerAndDefaultsEnabled() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let decision = try await store.beginBatch(targetBundleIdentifier: "com.example.first")
        XCTAssertEqual(decision.bindingMode, .fixedOwner)
        XCTAssertEqual(decision.fixedOwnerBundleIdentifier, "com.example.first")
        XCTAssertTrue(decision.initialSoftAssociations.isEmpty)
        XCTAssertTrue(decision.defaultsEnabled)
        let topology = PluginBindingTopology.forImport(pluginID: UUID(), decision: decision)
        XCTAssertTrue(topology.fixedOwnerIsEnabled, "First injection must be effective by default")
        try await store.completeSuccessfulBatch(decision.id, installedPluginCount: 2)
        let snapshot = await store.currentSnapshot()
        XCTAssertEqual(snapshot.successfulBatchCount, 1)
    }

    func testFailedOrCancelledFirstBatchDoesNotConsumeFirstBatchRule() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await store.beginBatch(targetBundleIdentifier: "com.example.first")
        do {
            try await store.completeSuccessfulBatch(first.id, installedPluginCount: 0)
            XCTFail("An empty batch must not be committed")
        } catch let error as PluginImportBatchPolicyError {
            XCTAssertEqual(error, .emptySuccessfulBatch)
        }
        try await store.cancelBatch(first.id)
        let retry = try await store.beginBatch(targetBundleIdentifier: "com.example.retry")
        XCTAssertEqual(retry.bindingMode, .fixedOwner)
    }

    func testSecondBatchUsesEnabledAdditionalAssociationAndPersistsAcrossRestart() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await store.beginBatch(targetBundleIdentifier: "com.example.first")
        try await store.completeSuccessfulBatch(first.id, installedPluginCount: 1)
        let second = try await store.beginBatch(targetBundleIdentifier: "com.example.second")
        XCTAssertEqual(second.bindingMode, .additionalAssociation)
        XCTAssertNil(second.fixedOwnerBundleIdentifier)
        XCTAssertEqual(second.initialSoftAssociations, [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.second", isEnabled: true)
        ])
        let secondTopology = PluginBindingTopology.forImport(pluginID: UUID(), decision: second)
        XCTAssertTrue(secondTopology.additionalAssociations.first?.isEnabled == true,
                      "An App receiving its first injected copy is enabled by default")
        try await store.completeSuccessfulBatch(second.id, installedPluginCount: 3)
        let restarted = try PluginImportBatchPolicyStore(stateURL: directory.appendingPathComponent("state.json"))
        let snapshot = await restarted.currentSnapshot()
        XCTAssertEqual(snapshot.successfulBatchCount, 2)
        let third = try await restarted.beginBatch(targetBundleIdentifier: "com.example.third")
        XCTAssertEqual(third.bindingMode, .additionalAssociation)
    }

    private func makeStore() throws -> (PluginImportBatchPolicyStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try PluginImportBatchPolicyStore(stateURL: directory.appendingPathComponent("state.json")), directory)
    }
}
