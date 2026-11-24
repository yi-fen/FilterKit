import Foundation

/// Retains the original plist bytes separately from the generated effective form.
struct PluginConfigurationSnapshot {
    let originalPlistData: Data?
    let originalSHA256: String?
    let effectivePlistData: Data
    let profileIdentifier: String
    let generatorVersion: String?
}
