import Foundation

/// Association type shown from an App's point of view. Hard binding is immutable;
/// soft association is independently enabled/disabled for each target App.
enum AppPluginAssociationKind: String, Codable, Equatable {
    case hardBound
    case softAssociated
    case filterMatched
}

enum AppPluginActivationObservedState: String, Codable, Equatable {
    case enabled
    case disabled
    case globalFilter
    case ambiguousFilter
    case inconsistent
    case unavailable
}

enum AppPluginActivationCrossCheck: String, Codable, Equatable {
    case matched
    case manifestFilterMismatch
    case manifestStateMissing
    case filterUnavailable
    case globalFilterCannotBeScoped
    case alternateMatchDimensionsPresent
}

struct AppPluginActivationState: Equatable, Identifiable {
    let pluginID: String
    let pluginName: String
    let targetBundleIdentifier: String
    let associationKind: AppPluginAssociationKind
    let observedState: AppPluginActivationObservedState
    let crossCheck: AppPluginActivationCrossCheck
    let isHardBound: Bool
    let canPreviewToggle: Bool
    let readOnlyReasonKey: String?

    var id: String { "\(pluginID)::\(targetBundleIdentifier)" }
    var isEnabled: Bool? {
        switch observedState {
        case .enabled: return true
        case .disabled: return false
        case .globalFilter, .ambiguousFilter, .inconsistent, .unavailable: return nil
        }
    }
}
