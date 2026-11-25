import Foundation

/// Inventory visibility is independent from management authorization.
/// The default list must show every discovered plugin, including unknown/package-owned
/// and unverified entries; the alternate scope is only a FilterKit ownership view.
enum PluginListScope {
    static func includes(_ item: PluginScanItem, filterKitOnly: Bool) -> Bool {
        guard filterKitOnly else { return true }
        return item.ownership == .filterKit || item.filterKitPluginID != nil
    }
}
