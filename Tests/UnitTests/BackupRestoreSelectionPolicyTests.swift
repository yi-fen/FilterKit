import XCTest
@testable import FilterKit

final class BackupRestoreSelectionPolicyTests: XCTestCase {
    func testOnlyReadyAndSoftAssociationMissingAreSelectable() {
        let ready = UUID()
        let softMissing = UUID()
        let hardMissing = UUID()
        let fileConflict = UUID()
        let identityConflict = UUID()
        let preview = BackupRestorePreview(plugins: [
            .init(pluginIdentifier: ready, disposition: .ready, missingBundleIdentifiers: [], conflictingFileNames: []),
            .init(pluginIdentifier: softMissing, disposition: .softAppsMissing, missingBundleIdentifiers: ["com.example.optional"], conflictingFileNames: []),
            .init(pluginIdentifier: hardMissing, disposition: .hardBoundAppMissing, missingBundleIdentifiers: ["com.example.source"], conflictingFileNames: []),
            .init(pluginIdentifier: fileConflict, disposition: .fileConflict, missingBundleIdentifiers: [], conflictingFileNames: ["Example.dylib"]),
            .init(pluginIdentifier: identityConflict, disposition: .identityConflict, missingBundleIdentifiers: [], conflictingFileNames: [])
        ])
        XCTAssertEqual(BackupRestoreSelectionPolicy.selectablePluginIDs(in: preview), [ready, softMissing])
    }
}
