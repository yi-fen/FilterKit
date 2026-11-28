import Foundation

/// User-facing binding mode chosen for an entire successful import batch.
enum PluginImportBindingMode: String, Codable, Equatable {
    /// The first successfully installed batch establishes immutable fixed ownership.
    case fixedOwner
    /// Later batches are associated with the importing App without establishing fixed ownership.
    case additionalAssociation
}

struct PluginImportBatchDecision: Codable, Equatable, Identifiable {
    let id: UUID
    let targetBundleIdentifier: String
    let bindingMode: PluginImportBindingMode
    let defaultsEnabled: Bool
    let isFirstSuccessfulBatch: Bool

    var fixedOwnerBundleIdentifier: String? {
        bindingMode == .fixedOwner ? targetBundleIdentifier : nil
    }

    var initialSoftAssociations: [FilterKitManifestSoftAssociation] {
        bindingMode == .additionalAssociation
            ? [FilterKitManifestSoftAssociation(bundleIdentifier: targetBundleIdentifier, isEnabled: defaultsEnabled)]
            : []
    }
}

struct PluginImportBatchPolicySnapshot: Codable, Equatable {
    let schemaVersion: Int
    let successfulBatchCount: UInt64
    let firstSuccessfulBatchID: UUID?
    let firstSuccessfulTargetBundleIdentifier: String?
    let lastSuccessfulBatchID: UUID?
    let updatedAt: Date?

    static let empty = PluginImportBatchPolicySnapshot(schemaVersion: 1,
        successfulBatchCount: 0, firstSuccessfulBatchID: nil,
        firstSuccessfulTargetBundleIdentifier: nil, lastSuccessfulBatchID: nil,
        updatedAt: nil)
}

enum PluginImportBatchPolicyError: Error, Equatable {
    case invalidTargetBundleIdentifier
    case batchAlreadyInProgress
    case noBatchInProgress
    case mismatchedBatchIdentifier
    case emptySuccessfulBatch
    case unsupportedStateVersion
    case corruptState
}

/// Persists the "first successful import batch" rule.
///
/// The in-flight reservation is deliberately memory-only: if the app exits before Helper
/// confirms the complete batch, the first-successful-batch privilege is not consumed.
/// Call `completeSuccessfulBatch` only after the entire Helper deployment transaction commits.
actor PluginImportBatchPolicyStore {
    private struct PersistedState: Codable {
        let snapshot: PluginImportBatchPolicySnapshot
    }

    private let stateURL: URL
    private var snapshot: PluginImportBatchPolicySnapshot
    private var activeDecision: PluginImportBatchDecision?

    init(stateURL: URL) throws {
        self.stateURL = stateURL
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do {
                let data = try Data(contentsOf: stateURL)
                let state = try JSONDecoder().decode(PersistedState.self, from: data)
                guard state.snapshot.schemaVersion == 1 else { throw PluginImportBatchPolicyError.unsupportedStateVersion }
                guard (state.snapshot.successfulBatchCount == 0) == (state.snapshot.firstSuccessfulBatchID == nil),
                      (state.snapshot.successfulBatchCount == 0) == (state.snapshot.firstSuccessfulTargetBundleIdentifier == nil) else {
                    throw PluginImportBatchPolicyError.corruptState
                }
                self.snapshot = state.snapshot
            } catch let error as PluginImportBatchPolicyError {
                throw error
            } catch {
                throw PluginImportBatchPolicyError.corruptState
            }
        } else {
            self.snapshot = .empty
        }
    }

    static func applicationSupportStore(fileManager: FileManager = .default) throws -> PluginImportBatchPolicyStore {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("FilterKit/ImportPolicy", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try PluginImportBatchPolicyStore(stateURL: directory.appendingPathComponent("successful-batches.json"))
    }

    func currentSnapshot() -> PluginImportBatchPolicySnapshot { snapshot }

    func beginBatch(targetBundleIdentifier: String) throws -> PluginImportBatchDecision {
        guard Self.isValidBundleIdentifier(targetBundleIdentifier) else {
            throw PluginImportBatchPolicyError.invalidTargetBundleIdentifier
        }
        guard activeDecision == nil else { throw PluginImportBatchPolicyError.batchAlreadyInProgress }
        let isFirst = snapshot.successfulBatchCount == 0
        let decision = PluginImportBatchDecision(id: UUID(),
            targetBundleIdentifier: targetBundleIdentifier,
            bindingMode: isFirst ? .fixedOwner : .additionalAssociation,
            defaultsEnabled: true,
            isFirstSuccessfulBatch: isFirst)
        activeDecision = decision
        return decision
    }

    func completeSuccessfulBatch(_ batchID: UUID, installedPluginCount: Int) throws {
        guard let activeDecision else { throw PluginImportBatchPolicyError.noBatchInProgress }
        guard activeDecision.id == batchID else { throw PluginImportBatchPolicyError.mismatchedBatchIdentifier }
        guard installedPluginCount > 0 else { throw PluginImportBatchPolicyError.emptySuccessfulBatch }

        let now = Date()
        let firstID = snapshot.firstSuccessfulBatchID ?? batchID
        let firstTarget = snapshot.firstSuccessfulTargetBundleIdentifier ?? activeDecision.targetBundleIdentifier
        let next = PluginImportBatchPolicySnapshot(schemaVersion: 1,
            successfulBatchCount: snapshot.successfulBatchCount + 1,
            firstSuccessfulBatchID: firstID,
            firstSuccessfulTargetBundleIdentifier: firstTarget,
            lastSuccessfulBatchID: batchID,
            updatedAt: now)
        try persist(next)
        snapshot = next
        self.activeDecision = nil
    }

    func cancelBatch(_ batchID: UUID) throws {
        guard let activeDecision else { throw PluginImportBatchPolicyError.noBatchInProgress }
        guard activeDecision.id == batchID else { throw PluginImportBatchPolicyError.mismatchedBatchIdentifier }
        self.activeDecision = nil
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 &&
            (part.first?.isLetter == true || part.first?.isNumber == true || part.first == "_") &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }
    }

    private func persist(_ value: PluginImportBatchPolicySnapshot) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(PersistedState(snapshot: value))
        try data.write(to: stateURL, options: .atomic)
        #if canImport(Darwin)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        #endif
    }
}
