import Foundation

/// Stable internal message identifiers; UI presentation resolves these through
/// Localizable.strings rather than persisting translated text.
enum FilterKitMessageCode: String {
    case importInvalidFile = "error.import.invalid_file"
    case importUnsupportedArchitecture = "error.import.unsupported_architecture"
    case importMalformedPlist = "error.import.malformed_plist"
    case pluginOwnershipConflict = "error.plugin.ownership_conflict"
    case deploymentVerificationFailed = "error.deployment.verification_failed"
    case backupIntegrityMismatch = "error.backup.integrity_mismatch"
    case storageCleanupFailed = "error.storage.cleanup_failed"
}
