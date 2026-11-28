import Foundation

/// Canonical comparison key for Bundle IDs at Helper trust and mutation boundaries.
/// The original spelling is retained in manifests and UI; only identity comparisons use this key.
enum HelperBundleIdentifierKey {
    static func make(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func set<S: Sequence>(_ values: S) -> Set<String> where S.Element == String {
        Set(values.map(make))
    }
}
