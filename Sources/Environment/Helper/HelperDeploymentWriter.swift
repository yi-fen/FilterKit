import Foundation

/// App-side staging writer. It only writes into the app-owned staging directory.
/// The returned requests are not sent while HelperDeploymentCoordinator.executionReleased is false.
final class HelperDeploymentWriter {
    enum WriterError: Error { case blockedRestoreItem(UUID), missingPayload(UUID) }
    private let stagingStore: HelperStagingStore

    init(stagingStore: HelperStagingStore) { self.stagingStore = stagingStore }

    func stageRestore(validated: [ValidatedBackupPlugin], selectedIDs: Set<UUID>,
                      preview: BackupRestorePreview, taskID: UUID) throws -> [HelperOperationRequest] {
        guard !selectedIDs.isEmpty else { throw HelperDeploymentPlanBuilder.PlanError.emptySelection }
        let previewByID = Dictionary(uniqueKeysWithValues: preview.plugins.map { ($0.pluginIdentifier, $0) })
        var requests: [HelperOperationRequest] = []
        for id in selectedIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let item = previewByID[id], item.disposition == .ready || item.disposition == .softAppsMissing else {
                throw WriterError.blockedRestoreItem(id)
            }
            guard let plugin = validated.first(where: { $0.entry.pluginIdentifier == id }) else { throw WriterError.missingPayload(id) }
            let dylib = try stagingStore.stage(data: plugin.dylibData, fileName: plugin.entry.dylibFileName, taskID: taskID)
            let plist = try stagingStore.stage(data: plugin.plistData, fileName: plugin.entry.plistFileName, taskID: taskID)
            requests.append(HelperOperationRequest(requestID: UUID(), operation: .installDylib,
                pluginID: id, stagingRelativePath: dylib.relativePath, targetFileName: plugin.entry.dylibFileName,
                expectedSHA256: dylib.sha256, createdAt: Date()))
            requests.append(HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist,
                pluginID: id, stagingRelativePath: plist.relativePath, targetFileName: plugin.entry.plistFileName,
                expectedSHA256: plist.sha256, createdAt: Date()))
        }
        return requests
    }
}
