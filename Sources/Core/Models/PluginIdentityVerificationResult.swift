import Foundation

/// A fail-closed interpretation of identity evidence already attached to a plugin scan.
/// This type does not create evidence or promote an unverified manifest; only a trusted
/// verifier may populate the underlying verified fields.
enum PluginIdentityVerificationStatus: String, Codable, Equatable {
    case verified
    case rejected
    case unverified
}

struct PluginIdentityVerificationResult: Equatable {
    let status: PluginIdentityVerificationStatus
    let reasonKey: String?

    var permitsActivationPreview: Bool { status == .verified }
}

struct PluginIdentityVerificationResolver {
    func resolve(plugin: PluginScanItem, now: Date = Date(), maximumAttestationAge: TimeInterval = HelperPluginIdentityAttestation.maximumAge) -> PluginIdentityVerificationResult {
        if plugin.ownership == .packageManager || plugin.ownershipConflict != .none || plugin.identityStatus == .duplicateIdentity
            || plugin.identityStatus == .installNameCollision
            || plugin.identityStatus == .uuidCDHashMismatch
            || plugin.identityStatus == .unresolvedBasenameCollision {
            return PluginIdentityVerificationResult(status: .rejected,
                reasonKey: "apps.detail.activation_identity_rejected")
        }
        guard let attestation = plugin.helperIdentityAttestation else {
            return PluginIdentityVerificationResult(status: .unverified,
                reasonKey: "apps.detail.activation_helper_attestation_required")
        }
        guard attestation.status != .rejected else {
            return PluginIdentityVerificationResult(status: .rejected,
                reasonKey: "apps.detail.activation_identity_rejected")
        }
        guard attestation.isFresh(now: now, maximumAge: maximumAttestationAge) else {
            return PluginIdentityVerificationResult(status: .unverified,
                reasonKey: "apps.detail.activation_helper_attestation_expired")
        }
        guard let helperAssociations = attestation.softAssociations,
              let scannedAssociations = plugin.softAssociationStates,
              let hardBoundBundleIdentifier = attestation.hardBoundBundleIdentifier,
              attestation.isVerified,
              attestation.pluginID?.uuidString.caseInsensitiveCompare(plugin.filterKitPluginID ?? "") == .orderedSame,
              attestation.dylibFileName == plugin.dylibFileName,
              attestation.plistFileName == plugin.plistFileName,
              attestation.dylibSHA256?.caseInsensitiveCompare(plugin.dylibSHA256 ?? "") == .orderedSame,
              attestation.plistSHA256?.caseInsensitiveCompare(plugin.plistSHA256 ?? "") == .orderedSame,
              attestation.manifestSHA256?.caseInsensitiveCompare(plugin.manifestSHA256 ?? "") == .orderedSame,
              hardBoundBundleIdentifier == plugin.hardBoundBundleIdentifier,
              Set(helperAssociations.map(\.bundleIdentifier)) == Set(plugin.softAssociatedBundleIdentifiers),
              helperAssociations.count == plugin.softAssociatedBundleIdentifiers.count,
              helperAssociations.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier }) ==
                scannedAssociations.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier }),
              attestation.machOIdentitySHA256?.caseInsensitiveCompare(plugin.identityFingerprint ?? "") == .orderedSame,
              attestation.filterConfiguration == plugin.filterConfiguration,
              Self.associationsMatchFilter(softAssociations: helperAssociations,
                  hardBoundBundleIdentifier: hardBoundBundleIdentifier,
                  filter: attestation.filterConfiguration) else {
            return PluginIdentityVerificationResult(status: .unverified,
                reasonKey: "apps.detail.activation_helper_attestation_mismatch")
        }
        return PluginIdentityVerificationResult(status: .verified, reasonKey: nil)
    }

    /// The complete soft-association set is cross-checked against Filter.Bundles.
    /// Disabled soft associations must be absent; enabled ones must be present.
    /// No unowned/undeclared bundle target is accepted. The hard binding remains
    /// a permanent relationship but may be absent from Bundles when disabled.
    private static func associationsMatchFilter(
        softAssociations: [FilterKitManifestSoftAssociation],
        hardBoundBundleIdentifier: String,
        filter: PluginFilterConfiguration?
    ) -> Bool {
        guard let filter, filter.parseState == .valid,
              filter.bundles.allSatisfy({ $0 != "*" }),
              Set(filter.bundles).count == filter.bundles.count,
              filter.classes.isEmpty, filter.executables.isEmpty else { return false }
        let enabledSoft = Set(softAssociations.filter(\.isEnabled).map(\.bundleIdentifier))
        let disabledSoft = Set(softAssociations.filter { !$0.isEnabled }.map(\.bundleIdentifier))
        let actual = Set(filter.bundles)
        let allowed = enabledSoft.union([hardBoundBundleIdentifier])
        return actual.isDisjoint(with: disabledSoft)
            && actual.isSubset(of: allowed)
            && actual.intersection(enabledSoft) == enabledSoft
    }

}
