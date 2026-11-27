import Foundation

/// Builds the App-detail activation view from the plugin manifest association state
/// and the actual parsed Filter.plist. It never writes either source and never infers
/// runtime injection from configuration membership.
struct AppPluginActivationStateResolver {
    func resolve(plugin: PluginScanItem, targetBundleIdentifier: String,
                 targetAppIsAvailable: Bool = true, now: Date = Date()) -> AppPluginActivationState? {
        let hardBound = plugin.hardBoundBundleIdentifier == targetBundleIdentifier
        let softBound = plugin.softAssociatedBundleIdentifiers.contains(targetBundleIdentifier)
        let filterMatches = plugin.filterConfiguration?.bundles.contains(targetBundleIdentifier) == true
            || plugin.filterConfiguration?.bundles.contains("*") == true
        guard hardBound || softBound || filterMatches else { return nil }

        let kind: AppPluginAssociationKind = hardBound ? .hardBound : (softBound ? .softAssociated : .filterMatched)
        let identityEvidence = PluginIdentityVerificationResolver().resolve(plugin: plugin, now: now)
        // Only fresh, fully cross-checked Helper evidence is authoritative. When
        // Helper is unavailable or stale, local scan data remains display-only.
        let filter = identityEvidence.permitsActivationPreview
            ? plugin.helperIdentityAttestation?.filterConfiguration
            : plugin.filterConfiguration
        let filterIsReadable = filter?.parseState == .valid
        let isGlobal = filterIsReadable && (filter?.bundles.contains("*") == true)
        let hasAlternateMatchDimensions = filterIsReadable
            && (!(filter?.classes.isEmpty ?? true) || !(filter?.executables.isEmpty ?? true))
        let filterListsTarget = filterIsReadable && (filter?.bundles.contains(targetBundleIdentifier) == true)

        var observed: AppPluginActivationObservedState = .unavailable
        var crossCheck: AppPluginActivationCrossCheck = .filterUnavailable
        if isGlobal {
            observed = .globalFilter
            crossCheck = .globalFilterCannotBeScoped
        } else if hasAlternateMatchDimensions {
            observed = .ambiguousFilter
            crossCheck = .alternateMatchDimensionsPresent
        } else if filterIsReadable {
            switch kind {
            case .hardBound, .filterMatched:
                observed = filterListsTarget ? .enabled : .disabled
                crossCheck = .matched
            case .softAssociated:
                let verifiedAssociations = plugin.helperIdentityAttestation?.softAssociations
                let manifestStates = (verifiedAssociations ?? plugin.softAssociationStates ?? []).filter {
                    $0.bundleIdentifier == targetBundleIdentifier
                }
                guard manifestStates.count == 1, let manifestState = manifestStates.first else {
                    observed = .inconsistent
                    crossCheck = manifestStates.isEmpty ? .manifestStateMissing : .manifestFilterMismatch
                    break
                }
                if manifestState.isEnabled == filterListsTarget {
                    observed = manifestState.isEnabled ? .enabled : .disabled
                    crossCheck = .matched
                } else {
                    observed = .inconsistent
                    crossCheck = .manifestFilterMismatch
                }
            }
        }

        let permissionAllows = identityEvidence.permitsActivationPreview
        let canPreview = permissionAllows && targetAppIsAvailable
            && kind != .filterMatched
            && (observed == .enabled || observed == .disabled)
            && crossCheck == .matched

        let reason: String?
        if !permissionAllows {
            reason = identityEvidence.reasonKey ?? "apps.detail.activation_read_only_unverified"
        } else if !targetAppIsAvailable {
            reason = "apps.detail.activation_read_only_app_missing"
        } else if kind == .filterMatched {
            reason = "apps.detail.activation_read_only_not_associated"
        } else if crossCheck != .matched {
            reason = "apps.detail.activation_read_only_mismatch"
        } else {
            reason = nil
        }

        return AppPluginActivationState(
            pluginID: plugin.id,
            pluginName: plugin.baseName,
            targetBundleIdentifier: targetBundleIdentifier,
            associationKind: kind,
            observedState: observed,
            crossCheck: crossCheck,
            isHardBound: hardBound,
            canPreviewToggle: canPreview,
            readOnlyReasonKey: reason
        )
    }
}
