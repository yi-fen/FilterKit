import Foundation

/// Narrow APP-detail command. It expresses one plugin's desired state for exactly one App.
/// `snapshotRevision` is an optimistic UI freshness hint only; Helper must still compare hashes
/// against its own freshly-read files before preparing any mutation.
struct HelperAppPluginActivationCommand: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let desiredEnabled: Bool
    let expectedEnabled: Bool
    let dylibFileName: String
    let plistFileName: String
    let expectedFilterSHA256: String
    let expectedManifestSHA256: String
    let snapshotRevision: UInt64
    let createdAt: Date

    func validate(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        guard requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              Self.validBundleIdentifier(targetBundleIdentifier),
              HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              HelperPolicy.isValidHash(expectedFilterSHA256),
              HelperPolicy.isValidHash(expectedManifestSHA256),
              snapshotRevision > 0,
              abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit else { return false }
        return true
    }

    /// Adapter to the existing Helper-owned mutation engine. No path or replacement bytes cross IPC.
    func makeMutationRequest() -> HelperPluginFilterMutationRequest {
        HelperPluginFilterMutationRequest(requestID: requestID, pluginID: pluginID,
            action: desiredEnabled ? .enableForApp : .disableForApp,
            dylibFileName: dylibFileName, plistFileName: plistFileName,
            targetBundleIdentifier: targetBundleIdentifier,
            expectedPlistSHA256: expectedFilterSHA256,
            expectedManifestSHA256: expectedManifestSHA256, createdAt: createdAt)
    }

    private static func validBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

/// Helper-authored single-App plan. It is a decision record, not a filesystem instruction.
struct HelperAppPluginActivationPlan: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let previousEnabled: Bool
    let desiredEnabled: Bool
    let filterBeforeSHA256: String
    let filterAfterSHA256: String
    let manifestBeforeSHA256: String
    let manifestAfterSHA256: String
    let changed: Bool

    func validates(command: HelperAppPluginActivationCommand) -> Bool {
        requestID == command.requestID && pluginID == command.pluginID &&
        targetBundleIdentifier == command.targetBundleIdentifier &&
        previousEnabled == command.expectedEnabled && desiredEnabled == command.desiredEnabled &&
        filterBeforeSHA256.caseInsensitiveCompare(command.expectedFilterSHA256) == .orderedSame &&
        manifestBeforeSHA256.caseInsensitiveCompare(command.expectedManifestSHA256) == .orderedSame &&
        HelperPolicy.isValidHash(filterAfterSHA256) && HelperPolicy.isValidHash(manifestAfterSHA256) &&
        changed == (previousEnabled != desiredEnabled)
    }
}


/// Commit must carry the exact Helper-authored Prepare plan. The plan is revalidated against
/// a fresh Helper authorization result at commit time; it is never treated as a filesystem command.
struct HelperAppPluginActivationCommitRequest: Codable, Equatable {
    /// A fresh transport request ID. It must differ from the Prepare command ID because
    /// the Helper replay guard consumes the Prepare ID exactly once.
    let requestID: UUID
    let createdAt: Date
    let command: HelperAppPluginActivationCommand
    let preparedPlan: HelperAppPluginActivationPlan

    func validates(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        requestID != command.requestID &&
        abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit &&
        command.validate(now: now, clockSkewLimit: clockSkewLimit) &&
        preparedPlan.validates(command: command)
    }
}

/// Commit proof is accepted only when it binds the exact command and both post-commit file hashes.
struct HelperAppPluginActivationProof: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let enabled: Bool
    let filterSHA256: String
    let manifestSHA256: String
    let transactionID: UUID?
    let completedAt: Date

    func validates(command: HelperAppPluginActivationCommand, now: Date = Date(), maximumAge: TimeInterval = 120) -> Bool {
        requestID == command.requestID && pluginID == command.pluginID &&
        targetBundleIdentifier == command.targetBundleIdentifier && enabled == command.desiredEnabled &&
        HelperPolicy.isValidHash(filterSHA256) && HelperPolicy.isValidHash(manifestSHA256) &&
        ((command.expectedEnabled == command.desiredEnabled && transactionID == nil) ||
         (command.expectedEnabled != command.desiredEnabled && transactionID != nil)) &&
        now.timeIntervalSince(completedAt) >= -5 && now.timeIntervalSince(completedAt) <= maximumAge
    }
}
