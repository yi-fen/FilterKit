import Foundation

/// A non-mutating preview of Bundle entries FilterKit may need to propose.
/// It deliberately does not serialize a replacement plist or authorize deployment.
struct FilterPlistAssociationPreview: Equatable {
    let parseState: PluginFilterParseState
    let containerKey: String
    let originalBundles: [String]
    let proposedBundles: [String]
    let proposedAdditions: [String]
    let removedBundles: [String]
    let unknownKeys: [String]
    let originalPlistSHA256: String
    let originalPlistData: Data
    let preservesOriginalBytes: Bool
    let requiresElleKitProfileVerification: Bool
    let canApply: Bool
    let reasonKey: String

    static func build(originalPlistData: Data, effectiveBundleIdentifiers: [String]) -> FilterPlistAssociationPreview {
        let configuration = PluginFilterConfiguration.parse(originalPlistData)
        let original = configuration.bundles
        let originalSet = Set(original)
        let requested = Array(Set(effectiveBundleIdentifiers)).sorted()
        let additions = requested.filter { !originalSet.contains($0) }
        let proposed = original + additions
        let valid = configuration.parseState == .valid
        return FilterPlistAssociationPreview(
            parseState: configuration.parseState,
            containerKey: configuration.containerKey,
            originalBundles: original,
            proposedBundles: proposed,
            proposedAdditions: additions,
            removedBundles: [],
            unknownKeys: configuration.unknownKeys,
            originalPlistSHA256: SHA256Digest.hex(originalPlistData),
            originalPlistData: originalPlistData,
            preservesOriginalBytes: true,
            requiresElleKitProfileVerification: true,
            canApply: false,
            reasonKey: valid ? "association.plist.preview_only" : "association.plist.invalid_original"
        )
    }
}
