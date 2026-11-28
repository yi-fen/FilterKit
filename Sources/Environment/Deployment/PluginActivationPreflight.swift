import Foundation

/// Read-only interpretation of the current Filter.plist. It is deliberately not a claim
/// that ElleKit accepted the filter or that the dylib was loaded into a process.
enum PluginFilterObservation: String, Codable, Equatable {
    case targetListed
    case targetNotListed
    case globalFilter
    case unavailable
}

enum PluginActivationPreflightBlocker: String, Codable, Equatable, CaseIterable {
    case unsupportedEnvironment
    case elleKitNotDetected
    case pluginNotFilterKitOwned
    case pluginPairNotValid
    case managementPermissionDenied
    case targetAppUnavailable
    /// Deprecated compatibility case. Hard binding is not an activation blocker.
    case hardBoundAppCannotBeToggled
    case invalidTargetBundleIdentifier
    case enableDisableStrategyUnverified
    case helperUnavailable
    case recoveryNotClean
    case mutationReleaseClosed
}

enum PluginActivationPreflightDisposition: String, Codable, Equatable {
    case inspectionOnly
    case blocked
    case readyForFutureMutation
}

struct PluginActivationPreflightInput {
    let ownership: PluginOwnership
    let pairing: PluginPairingState
    let permission: PluginManagementPermission
    let isHardBoundApp: Bool
    let targetBundleIdentifier: String
    let targetAppIsAvailable: Bool
    let environment: JailbreakEnvironmentKind
    let elleKitIsPresent: Bool
    let strategy: EnableDisableStrategyResolution
    let helperIsReachable: Bool
    let recoveryIsClean: Bool
    let filterConfiguration: PluginFilterConfiguration?
}

struct PluginActivationPreflightReport: Codable, Equatable {
    let inspectedAt: Date
    let targetBundleIdentifier: String
    let disposition: PluginActivationPreflightDisposition
    let blockers: [PluginActivationPreflightBlocker]
    let filterObservation: PluginFilterObservation
    let desiredState: PluginDesiredState
    let runtimeState: PluginRuntimeState
    let canMutate: Bool

    /// This release intentionally never authorizes mutation. A future release must add
    /// a separately reviewed Helper operation and device-verified ElleKit profile.
    static let mutationReleaseEnabled = false
}

/// Produces a deterministic, read-only preflight. It does not access files or contact Helper.
/// Callers must supply observations obtained from the existing scanners and Helper health check.
struct PluginActivationPreflight {
    func evaluate(_ input: PluginActivationPreflightInput,
                  desiredState: PluginDesiredState,
                  inspectedAt: Date = Date()) -> PluginActivationPreflightReport {
        var blockers: [PluginActivationPreflightBlocker] = []

        if input.environment != .rootHide && input.environment != .rootless {
            blockers.append(.unsupportedEnvironment)
        }
        if !input.elleKitIsPresent { blockers.append(.elleKitNotDetected) }
        if input.ownership != .filterKit { blockers.append(.pluginNotFilterKitOwned) }
        if input.pairing != .paired { blockers.append(.pluginPairNotValid) }
        if !input.permission.canModify { blockers.append(.managementPermissionDenied) }
        // Hard binding cannot be removed, but its activation state is independently controllable.
        if !input.targetAppIsAvailable { blockers.append(.targetAppUnavailable) }
        if !Self.isValidBundleIdentifier(input.targetBundleIdentifier) {
            blockers.append(.invalidTargetBundleIdentifier)
        }
        if !input.strategy.permitsMutation { blockers.append(.enableDisableStrategyUnverified) }
        if !input.helperIsReachable { blockers.append(.helperUnavailable) }
        if !input.recoveryIsClean { blockers.append(.recoveryNotClean) }

        if !PluginActivationPreflightReport.mutationReleaseEnabled {
            blockers.append(.mutationReleaseClosed)
        }
        let filterObservation = Self.observeFilter(input.filterConfiguration,
                                                   targetBundleIdentifier: input.targetBundleIdentifier)
        // Runtime state is never inferred from a plist or a successful preflight.
        let substantiveBlockers = blockers.filter { $0 != .mutationReleaseClosed }
        let disposition: PluginActivationPreflightDisposition
        if !substantiveBlockers.isEmpty {
            disposition = .blocked
        } else if PluginActivationPreflightReport.mutationReleaseEnabled {
            disposition = .readyForFutureMutation
        } else {
            disposition = .inspectionOnly
        }
        let canMutate = disposition == .readyForFutureMutation
        return PluginActivationPreflightReport(
            inspectedAt: inspectedAt,
            targetBundleIdentifier: input.targetBundleIdentifier,
            disposition: disposition,
            blockers: blockers,
            filterObservation: filterObservation,
            desiredState: desiredState,
            runtimeState: .notObserved,
            canMutate: canMutate
        )
    }

    private static func observeFilter(_ configuration: PluginFilterConfiguration?,
                                      targetBundleIdentifier: String) -> PluginFilterObservation {
        guard let configuration, configuration.parseState == .valid || configuration.parseState == .partial else {
            return .unavailable
        }
        if configuration.bundles.contains("*") { return .globalFilter }
        let bundleKeys = HelperBundleIdentifierKey.set(configuration.bundles)
        return bundleKeys.contains(HelperBundleIdentifierKey.make(targetBundleIdentifier)) ? .targetListed : .targetNotListed
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard value.count <= 255, !value.isEmpty else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 &&
            (part.first?.isLetter == true || part.first?.isNumber == true) &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
