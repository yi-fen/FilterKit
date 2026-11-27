import Foundation

/// Pure, App-scoped preview state. This is deliberately separate from persisted
/// Filter/Manifest state and can only influence the UI until a future release gate.
struct AppPluginActivationPreviewLedger {
    private(set) var snapshotID: String?
    private var values: [String: Bool] = [:]

    mutating func updateSnapshot(_ newSnapshotID: String?) {
        guard snapshotID != newSnapshotID else { return }
        snapshotID = newSnapshotID
        values.removeAll()
    }

    mutating func setPreview(_ value: Bool, pluginID: String,
                             targetBundleIdentifier: String, snapshotID: String?) {
        updateSnapshot(snapshotID)
        values[key(pluginID: pluginID, bundleID: targetBundleIdentifier)] = value
    }

    func preview(pluginID: String, targetBundleIdentifier: String) -> Bool? {
        values[key(pluginID: pluginID, bundleID: targetBundleIdentifier)]
    }

    private func key(pluginID: String, bundleID: String) -> String {
        "\(pluginID)::\(bundleID)"
    }
}
