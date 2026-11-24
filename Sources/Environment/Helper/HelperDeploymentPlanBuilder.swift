import Foundation

/// Converts an already-reviewed backup selection into a deterministic, closed plan.
/// It never writes to the jailbreak filesystem and emits no shell command or argv.
struct HelperDeploymentPlanBuilder {
    enum PlanError: Error, Equatable { case emptySelection, blockedPlugin(UUID), missingPayload(UUID), invalidManifest(UUID) }

    func build(validated: [ValidatedBackupPlugin], selectedIDs: Set<UUID>,
               preview: BackupRestorePreview) throws -> [HelperOperationRequest] {
        guard !selectedIDs.isEmpty else { throw PlanError.emptySelection }
        let previewByID = Dictionary(uniqueKeysWithValues: preview.plugins.map { ($0.pluginIdentifier, $0) })
        var requests: [HelperOperationRequest] = []
        for id in selectedIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let item = previewByID[id], item.disposition == .ready || item.disposition == .softAppsMissing else { throw PlanError.blockedPlugin(id) }
            guard let plugin = validated.first(where: { $0.entry.pluginIdentifier == id }) else { throw PlanError.missingPayload(id) }
            let entry = plugin.entry
            guard entry.dylibFileName.lowercased().hasSuffix(".dylib"), entry.plistFileName.lowercased().hasSuffix(".plist") else { throw PlanError.invalidManifest(id) }
            // The caller stages payload bytes and supplies a task-local relative path in a later phase.
            requests.append(HelperOperationRequest(requestID: UUID(), operation: .installDylib,
                pluginID: id, stagingRelativePath: nil, targetFileName: entry.dylibFileName,
                expectedSHA256: entry.dylibSHA256, createdAt: Date()))
            requests.append(HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist,
                pluginID: id, stagingRelativePath: nil, targetFileName: entry.plistFileName,
                expectedSHA256: entry.plistSHA256, createdAt: Date()))
        }
        return requests
    }
}

/// Only creates task-scoped files inside the app's own container. It is not a privileged writer.
final class HelperStagingStore {
    enum StagingError: Error { case invalidTaskID, unsafeRoot, unsafeName, writeFailed }
    private let fileManager: FileManager
    private let rootURL: URL

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let values = try self.rootURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw StagingError.unsafeRoot }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.rootURL.path)
    }

    func stage(data: Data, fileName: String, taskID: UUID) throws -> (relativePath: String, sha256: String) {
        guard HelperPolicy.isSafeLeafName(fileName) else { throw StagingError.unsafeName }
        let taskName = taskID.uuidString.lowercased()
        let taskURL = rootURL.appendingPathComponent(taskName, isDirectory: true)
        try fileManager.createDirectory(at: taskURL, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let destination = taskURL.appendingPathComponent(fileName, isDirectory: false)
        guard destination.deletingLastPathComponent().standardizedFileURL == taskURL.standardizedFileURL else { throw StagingError.unsafeName }
        guard !fileManager.fileExists(atPath: destination.path) else { throw StagingError.writeFailed }
        do {
            try data.write(to: destination, options: [.withoutOverwriting, .completeFileProtectionUnlessOpen])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch { throw StagingError.writeFailed }
        return ("\(taskName)/\(fileName)", SHA256Digest.hex(data))
    }

    func removeTask(_ taskID: UUID) throws {
        let taskURL = rootURL.appendingPathComponent(taskID.uuidString.lowercased(), isDirectory: true).standardizedFileURL
        guard taskURL.deletingLastPathComponent() == rootURL.standardizedFileURL else { throw StagingError.invalidTaskID }
        let values = try? taskURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true else { throw StagingError.unsafeRoot }
        if fileManager.fileExists(atPath: taskURL.path) { try fileManager.removeItem(at: taskURL) }
    }
}
