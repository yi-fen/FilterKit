import Foundation

/// Canonical Bundle ID comparisons shared by backup validation, export, and restore preview.
/// Original Bundle ID spelling is retained in the backup; canonical keys are comparison-only.
enum BackupBundleIdentity {
    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?):
            return HelperBundleIdentifierKey.make(left) == HelperBundleIdentifierKey.make(right)
        default: return false
        }
    }

    static func sameSet(_ lhs: [String], _ rhs: [String]) -> Bool {
        let left = HelperBundleIdentifierKey.set(lhs)
        let right = HelperBundleIdentifierKey.set(rhs)
        return left.count == lhs.count && right.count == rhs.count && left == right
    }

    static func sameStates(_ lhs: [(bundleIdentifier: String, isEnabled: Bool)],
                           _ rhs: [(bundleIdentifier: String, isEnabled: Bool)]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        func index(_ values: [(bundleIdentifier: String, isEnabled: Bool)]) -> [String: Bool]? {
            var result: [String: Bool] = [:]
            for value in values {
                let key = HelperBundleIdentifierKey.make(value.bundleIdentifier)
                guard !key.isEmpty, result[key] == nil else { return nil }
                result[key] = value.isEnabled
            }
            return result
        }
        guard let left = index(lhs), let right = index(rhs) else { return false }
        return left == right
    }
}
