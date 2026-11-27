import Foundation

/// Monotonic token source for read-only inventory scans. Completion handlers may
/// publish only if their token is still current after a newer refresh begins.
struct PluginScanGenerationTracker: Equatable {
    private(set) var current: UInt64 = 0

    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    func isCurrent(_ token: UInt64) -> Bool {
        token == current
    }
}
