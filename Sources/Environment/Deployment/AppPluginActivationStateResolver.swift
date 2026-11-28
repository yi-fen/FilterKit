import Foundation

/// Builds the App-detail activation view from the plugin manifest association state
/// and the actual parsed Filter.plist. It never writes either source and never infers
/// runtime injection from configuration membership.
struct AppPluginActivationStateResolver {
    func resolve(plugin: PluginScanItem, targetBundleIdentifier: String,
                 targetAppIsAvailable: Bool = true, now: Date = Date()) -> AppPluginActivationState? {
        let targetKey = HelperBundleIdentifierKey.make(targetBundleIdentifier)
        let hardBound = plugin.hardBoundBundleIdentifier.map {
            HelperBundleIdentifierKey.make($0) == targetKey
        } ?? false
        let softBound = plugin.softAssociatedBundleIdentifiers.contains {
            HelperBundleIdentifierKey.make($0) == targetKey
        }
        let filterBundleKeys = HelperBundleIdentifierKey.set(plugin.filterConfiguration?.bundles ?? [])
        let filterMatches = filterBundleKeys.contains(targetKey) || filterBundleKeys.contains("*")
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
        let filterListsTarget = filterIsReadable
            && HelperBundleIdentifierKey.set(filter?.bundles ?? []).contains(targetKey)

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
                    HelperBundleIdentifierKey.make($0.bundleIdentifier) == targetKey
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
