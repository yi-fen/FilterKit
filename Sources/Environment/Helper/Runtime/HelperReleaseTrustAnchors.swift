import Foundation

/// Compile-time release trust anchors. The checked-in value is intentionally empty.
/// A release build must replace this file with output from configure-helper-release-keys.py;
/// an empty key set is a hard startup failure, never a development fallback.
enum HelperReleaseTrustAnchors {
    static let keys: [HelperReleaseSigningKey] = []
}
