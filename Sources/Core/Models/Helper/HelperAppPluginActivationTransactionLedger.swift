import Foundation

/// Helper-owned, append-only state description for one APP activation command.
/// The schema is intentionally path-free and contains no caller-supplied filesystem locations.
struct HelperAppPluginActivationTransactionRecord: Codable, Equatable {
    enum State: String, Codable {
        case executing
        case committed
        case rolledBack
        case outcomeUnknown
    }

    let schemaVersion: Int
    let commandRequestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let desiredEnabled: Bool
    let transactionID: UUID
    let filterBeforeSHA256: String
    let manifestBeforeSHA256: String
    let filterAfterSHA256: String
    let manifestAfterSHA256: String
    private(set) var state: State
    private(set) var sequence: UInt64
    let createdAt: Date
    private(set) var updatedAt: Date

    enum LedgerError: Error, Equatable {
        case invalidRecord
        case invalidTransition
        case staleUpdate
    }

    init(command: HelperAppPluginActivationCommand, plan: HelperAppPluginActivationPlan,
         transactionID: UUID, now: Date = Date()) throws {
        guard plan.validates(command: command), plan.changed,
              transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            throw LedgerError.invalidRecord
        }
        schemaVersion = 1
        commandRequestID = command.requestID
        pluginID = command.pluginID
        targetBundleIdentifier = command.targetBundleIdentifier
        desiredEnabled = command.desiredEnabled
        self.transactionID = transactionID
        filterBeforeSHA256 = plan.filterBeforeSHA256.lowercased()
        manifestBeforeSHA256 = plan.manifestBeforeSHA256.lowercased()
        filterAfterSHA256 = plan.filterAfterSHA256.lowercased()
        manifestAfterSHA256 = plan.manifestAfterSHA256.lowercased()
        state = .executing
        sequence = 0
        createdAt = now
        updatedAt = now
    }

    mutating func transition(to next: State, now: Date = Date()) throws {
        guard now >= updatedAt else { throw LedgerError.staleUpdate }
        let allowed: Bool
        switch (state, next) {
        case (.executing, .committed), (.executing, .rolledBack), (.executing, .outcomeUnknown): allowed = true
        case (.outcomeUnknown, .committed), (.outcomeUnknown, .rolledBack): allowed = true
        default: allowed = false
        }
        guard allowed else { throw LedgerError.invalidTransition }
        guard sequence < UInt64.max else { throw LedgerError.invalidRecord }
        state = next
        sequence += 1
        updatedAt = now
    }

    func validate() throws {
        guard schemaVersion == 1,
              commandRequestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              !targetBundleIdentifier.isEmpty, targetBundleIdentifier.utf8.count <= 255,
              HelperPolicy.isValidHash(filterBeforeSHA256), HelperPolicy.isValidHash(manifestBeforeSHA256),
              HelperPolicy.isValidHash(filterAfterSHA256), HelperPolicy.isValidHash(manifestAfterSHA256),
              updatedAt >= createdAt else { throw LedgerError.invalidRecord }
        if state == .executing { guard sequence == 0 else { throw LedgerError.invalidRecord } }
        else { guard sequence > 0 else { throw LedgerError.invalidRecord } }
    }
}

/// Read-only transaction status lookup. The lookup key is the original command ID, not the
/// transport request ID, so a reconnect can query the same Helper transaction safely.
struct HelperAppPluginActivationTransactionQuery: Codable, Equatable {
    let requestID: UUID
    let commandRequestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let createdAt: Date

    func validate(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        requestID != commandRequestID &&
        requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        commandRequestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        !targetBundleIdentifier.isEmpty && targetBundleIdentifier.utf8.count <= 255 &&
        abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit
    }
}

/// Explicit, user-confirmed request to reconcile a previously unknown Helper transaction.
/// Unlike status lookup, this request may persist a verified terminal Ledger state and clean
/// only the matching transaction journal after that Ledger write succeeds.
struct HelperAppPluginActivationTransactionReconciliationRequest: Codable, Equatable {
    let requestID: UUID
    let commandRequestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let createdAt: Date
    let operatorConfirmed: Bool

    func validate(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        requestID != commandRequestID &&
        requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        commandRequestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        !targetBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        targetBundleIdentifier.utf8.count <= 255 && operatorConfirmed &&
        abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit
    }

    var statusQuery: HelperAppPluginActivationTransactionQuery {
        HelperAppPluginActivationTransactionQuery(requestID: requestID,
            commandRequestID: commandRequestID, pluginID: pluginID,
            targetBundleIdentifier: targetBundleIdentifier, createdAt: createdAt)
    }
}

struct HelperAppPluginActivationTransactionStatus: Codable, Equatable {
    let queryRequestID: UUID
    let commandRequestID: UUID
    let pluginID: UUID
    let targetBundleIdentifier: String
    let state: HelperAppPluginActivationTransactionRecord.State?
    let transactionID: UUID?
    let filterSHA256: String?
    let manifestSHA256: String?
    let checkedAt: Date

    func matches(_ query: HelperAppPluginActivationTransactionQuery) -> Bool {
        guard queryRequestID == query.requestID,
              commandRequestID == query.commandRequestID,
              pluginID == query.pluginID,
              HelperBundleIdentifierKey.make(targetBundleIdentifier) == HelperBundleIdentifierKey.make(query.targetBundleIdentifier) else { return false }
        if state == nil { return transactionID == nil && filterSHA256 == nil && manifestSHA256 == nil }
        guard let transactionID, transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { return false }
        if let filterSHA256, !HelperPolicy.isValidHash(filterSHA256) { return false }
        if let manifestSHA256, !HelperPolicy.isValidHash(manifestSHA256) { return false }
        if state == .committed {
            guard filterSHA256 != nil, manifestSHA256 != nil else { return false }
        }
        return true
    }
}
