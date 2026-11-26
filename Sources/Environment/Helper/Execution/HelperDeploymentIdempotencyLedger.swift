import Foundation

/// Deployment retry guard. When configured with a durable store, batch identity and terminal
/// state survive Helper restart. In-flight records are conservatively restored as indeterminate.
final class HelperDeploymentIdempotencyLedger {
    enum State: Equatable { case inProgress, completed, indeterminate, rolledBack }
    enum Decision: Equatable {
        case accepted
        case existing(State)
        case conflict
    }
    private struct Entry: Equatable {
        let digest: String
        let requestIDs: [UUID]
        let transactionID: UUID?
        var state: State
    }
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var operationOwners: [UUID: UUID] = [:]
    private let capacity: Int
    private let durableStore: HelperDeploymentDurableLedgerStore?
    private var storageUnavailable = false

    init(capacity: Int = 256, durableStore: HelperDeploymentDurableLedgerStore? = nil) {
        self.capacity = min(256, max(1, capacity))
        self.durableStore = durableStore
        if let durableStore {
            do {
                let records = try durableStore.load()
                guard records.count <= self.capacity else { throw HelperDeploymentDurableLedgerStore.StoreError.invalidData }
                for record in records {
                    let state: State
                    switch record.state {
                    case .inProgress: state = .indeterminate // process restart makes an in-flight outcome uncertain
                    case .completed: state = .completed
                    case .indeterminate: state = .indeterminate
                    case .rolledBack: state = .rolledBack
                    }
                    entries[record.batchID] = Entry(digest: record.digest, requestIDs: record.requestIDs, transactionID: record.transactionID, state: state)
                    for id in record.requestIDs { operationOwners[id] = record.batchID }
                }
            } catch { storageUnavailable = true }
        }
    }

    func begin(batchID: UUID, digest: String, requestIDs: [UUID], transactionID: UUID? = nil) -> Decision {
        guard HelperPolicy.isValidHash(digest), !requestIDs.isEmpty,
              Set(requestIDs).count == requestIDs.count else { return .conflict }
        lock.lock(); defer { lock.unlock() }
        guard !storageUnavailable else { return .conflict }
        if let entry = entries[batchID] {
            guard entry.digest == digest.lowercased(), entry.requestIDs == requestIDs else { return .conflict }
            return .existing(entry.state)
        }
        guard entries.count < capacity,
              requestIDs.allSatisfy({ operationOwners[$0] == nil }) else { return .conflict }
        entries[batchID] = Entry(digest: digest.lowercased(), requestIDs: requestIDs, transactionID: transactionID, state: .inProgress)
        for requestID in requestIDs { operationOwners[requestID] = batchID }
        guard persist(batchID: batchID, transactionID: transactionID, state: .inProgress) else {
            entries.removeValue(forKey: batchID)
            for requestID in requestIDs { operationOwners.removeValue(forKey: requestID) }
            storageUnavailable = true
            return .conflict
        }
        return .accepted
    }

    @discardableResult
    func finish(batchID: UUID, digest: String, state: State) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[batchID], entry.digest == digest.lowercased() else { return false }
        entry.state = state
        entries[batchID] = entry
        guard persist(batchID: batchID, transactionID: entry.transactionID, state: state) else {
            storageUnavailable = true
            return false
        }
        return true
    }

    private func persist(batchID: UUID, transactionID: UUID?, state: State) -> Bool {
        guard let durableStore else { return true }
        do {
            var records = try durableStore.load()
            guard let entry = entries[batchID] else { return false }
            let durableState: HelperDeploymentDurableLedgerStore.Record.State
            switch state {
            case .inProgress: durableState = .inProgress
            case .completed: durableState = .completed
            case .indeterminate: durableState = .indeterminate
            case .rolledBack: durableState = .rolledBack
            }
            let record = HelperDeploymentDurableLedgerStore.Record(batchID: batchID, digest: entry.digest,
                requestIDs: entry.requestIDs, transactionID: transactionID, state: durableState, updatedAt: Date())
            if let index = records.firstIndex(where: { $0.batchID == batchID }) { records[index] = record }
            else { guard records.count < min(256, capacity) else { return false }; records.append(record) }
            try durableStore.save(records)
            return true
        } catch { return false }
    }
}
