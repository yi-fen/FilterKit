import Foundation
import SwiftUI

/// Observable UI adapter around the pure App-scoped preview ledger.
@MainActor
final class AppPluginActivationPreviewStore: ObservableObject {
    static let shared = AppPluginActivationPreviewStore()

    @Published private(set) var revision: UInt64 = 0
    private var ledger = AppPluginActivationPreviewLedger()

    func preview(for state: AppPluginActivationState) -> Bool? {
        ledger.preview(pluginID: state.pluginID, targetBundleIdentifier: state.targetBundleIdentifier)
    }

    func setPreview(_ value: Bool, for state: AppPluginActivationState, snapshotID: String?) {
        ledger.setPreview(value, pluginID: state.pluginID,
                          targetBundleIdentifier: state.targetBundleIdentifier,
                          snapshotID: snapshotID)
        revision &+= 1
    }

    func updateSnapshot(_ snapshotID: String?) {
        let oldRevision = ledger.snapshotID
        ledger.updateSnapshot(snapshotID)
        if oldRevision != snapshotID { revision &+= 1 }
    }
}
