import Foundation

/// In-memory replay guard. A production daemon must persist/reseed this state across restarts
/// or bind requests to a fresh authenticated session nonce.
actor HelperReplayGuard {
    private let retention: TimeInterval
    private let capacity: Int
    private var seen: [UUID: Date] = [:]

    init(retention: TimeInterval = 600, capacity: Int = 4096) {
        self.retention = retention
        self.capacity = max(1, capacity)
    }

    func accept(_ requestID: UUID, now: Date = Date()) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) <= retention }
        guard seen[requestID] == nil else { return false }
        if seen.count >= capacity {
            let oldest = seen.min { $0.value < $1.value }?.key
            if let oldest { seen.removeValue(forKey: oldest) }
        }
        seen[requestID] = now
        return true
    }
}
