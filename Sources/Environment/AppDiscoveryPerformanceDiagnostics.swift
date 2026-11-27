import Foundation

/// Process-local counters for app discovery and entry-path I/O. No persistence or upload.
enum AppDiscoveryPerformanceDiagnostics {
    struct Snapshot {
        let proxyCalls: [String: Int]
        let proxyHits: [String: Int]
        let plistReads: Int
        let appPageEntries: Int
        let warmInventoryEntries: Int
        let pluginSnapshotHits: Int
        let pluginSnapshotMisses: Int
        let iconFileReads: Int
        let iconAssetReads: Int
        let secondEntryIconFileReads: Int
    }

    private static let lock = NSLock()
    private static var calls: [String: Int] = [:]
    private static var hits: [String: Int] = [:]
    private static var plistReadCount = 0
    private static var pageEntries = 0
    private static var warmEntries = 0
    private static var pluginHits = 0
    private static var pluginMisses = 0
    private static var fileReads = 0
    private static var assetReads = 0
    private static var secondEntryFileReads = 0

    static func recordProxy(selector: String, hit: Bool) {
        lock.lock(); defer { lock.unlock() }
        calls[selector, default: 0] += 1
        if hit { hits[selector, default: 0] += 1 }
    }
    static func recordInfoPlistRead() { lock.lock(); plistReadCount += 1; lock.unlock() }
    static func recordAppPageEntry(warmInventory: Bool) {
        lock.lock(); pageEntries += 1; if warmInventory { warmEntries += 1 }; lock.unlock()
    }
    static func recordPluginSnapshot(hit: Bool) {
        lock.lock(); if hit { pluginHits += 1 } else { pluginMisses += 1 }; lock.unlock()
    }
    static func recordIconFileRead() {
        lock.lock(); fileReads += 1
        if pageEntries == 2 { secondEntryFileReads += 1 }
        lock.unlock()
    }
    static func recordIconAssetRead() { lock.lock(); assetReads += 1; lock.unlock() }

    static func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(proxyCalls: calls, proxyHits: hits, plistReads: plistReadCount,
            appPageEntries: pageEntries, warmInventoryEntries: warmEntries,
            pluginSnapshotHits: pluginHits, pluginSnapshotMisses: pluginMisses,
            iconFileReads: fileReads, iconAssetReads: assetReads,
            secondEntryIconFileReads: secondEntryFileReads)
    }

    static func logSummaryIfNeeded() {
        #if DEBUG
        let s = snapshot()
        let methods = s.proxyCalls.keys.sorted().map { key in
            let count = s.proxyCalls[key, default: 0]
            let hit = s.proxyHits[key, default: 0]
            return "\(key)=\(hit)/\(count)"
        }.joined(separator: ",")
        NSLog("[FilterKit][AppDiscovery][R4] proxy_methods={%@} plist_reads=%d app_entries=%d warm_inventory_entries=%d plugin_snapshot_hits=%d plugin_snapshot_misses=%d icon_file_reads=%d icon_asset_reads=%d second_entry_icon_file_reads=%d",
              methods, s.plistReads, s.appPageEntries, s.warmInventoryEntries,
              s.pluginSnapshotHits, s.pluginSnapshotMisses, s.iconFileReads, s.iconAssetReads,
              s.secondEntryIconFileReads)
        #endif
    }
}
