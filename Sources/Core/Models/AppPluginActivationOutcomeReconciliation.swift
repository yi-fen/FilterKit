import Foundation

/// A fresh read-only inventory can help explain a lost Commit response, but it is not a
/// Helper-authored Commit proof. The three outcomes deliberately preserve that distinction.
enum AppPluginActivationOutcomeResolution: String, Equatable {
    case desiredStateObserved
    case previousStateObserved
    case stillIndeterminate
}

struct AppPluginActivationOutcomeReconciler {
    func resolve(command: HelperAppPluginActivationCommand,
                 observed: AppPluginActivationState?) -> AppPluginActivationOutcomeResolution {
        guard let observed,
              UUID(uuidString: observed.pluginID) == command.pluginID,
              HelperBundleIdentifierKey.make(observed.targetBundleIdentifier)
                == HelperBundleIdentifierKey.make(command.targetBundleIdentifier),
              observed.crossCheck == .matched,
              let enabled = observed.isEnabled else {
            return .stillIndeterminate
        }
        if enabled == command.desiredEnabled { return .desiredStateObserved }
        if enabled == command.expectedEnabled { return .previousStateObserved }
        return .stillIndeterminate
    }
}
