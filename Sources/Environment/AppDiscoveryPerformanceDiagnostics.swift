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
        let s = snapshot()
        let methods = s.proxyCalls.keys.sorted().map { key in
            let count = s.proxyCalls[key, default: 0]
            let hit = s.proxyHits[key, default: 0]
            return "\(key)=\(hit)/\(count)"
        }.joined(separator: ",")
        let line = "[AppDiscovery][P2-39-R3] proxy_methods={\(methods)} plist_reads=\(s.plistReads) app_entries=\(s.appPageEntries) warm_inventory_entries=\(s.warmInventoryEntries) plugin_snapshot_hits=\(s.pluginSnapshotHits) plugin_snapshot_misses=\(s.pluginSnapshotMisses) icon_file_reads=\(s.iconFileReads) icon_asset_reads=\(s.iconAssetReads) second_entry_icon_file_reads=\(s.secondEntryIconFileReads)"
        RuntimeDiagnosticsStore.append(line)
        #if DEBUG
        NSLog("[FilterKit] %@", line)
        #endif
    }
}
