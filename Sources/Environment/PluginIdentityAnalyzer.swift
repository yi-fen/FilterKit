import Foundation

/// Compares independently scanned plugin records. Fingerprints are evidence for
/// inventory reconciliation only; they never grant ownership or management rights.
struct PluginIdentityAnalyzer {
    struct Analysis {
        let items: [PluginScanItem]
        let conflicts: [PluginIdentityConflict]
    }

    func analyze(_ input: [PluginScanItem]) -> Analysis {
        var items = input
        var conflicts: [PluginIdentityConflict] = []

        for index in items.indices {
            let item = items[index]
            let uuids = normalized(item.machOUUIDs.isEmpty ? (item.machOUUID.map { [$0] } ?? []) : item.machOUUIDs)
            let cdHashes = normalized(item.machOCDHashes)
            let installName = item.machOInstallName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let fingerprint = Self.fingerprint(installNames: installName.map { [$0] } ?? [],
                                                   uuids: uuids, cdHashes: cdHashes,
                                                   architectures: item.machOArchitectures) {
                items[index].identityFingerprint = fingerprint
                items[index].identityStatus = .unique
            } else {
                items[index].identityFingerprint = nil
                items[index].identityStatus = .insufficientFingerprint
            }
            if item.pairingState == .invalid && item.warnings.contains("plugin_scan.duplicate_case_insensitive_basename") {
                items[index].identityStatus = .unresolvedBasenameCollision
            }
        }

        func record(_ kind: PluginIdentityStatus, _ indices: [Int], _ detail: String) {
            let ids = indices.map { items[$0].id }.sorted()
            let conflictID = "\(kind.rawValue):\(ids.joined(separator: "|"))"
            conflicts.append(PluginIdentityConflict(id: conflictID, kind: kind, pluginIDs: ids, detail: detail))
            for index in indices {
                items[index].identityStatus = kind
                items[index].identityConflictIDs.append(conflictID)
            }
        }

        let fingerprintGroups = Dictionary(grouping: items.indices.filter { items[$0].identityFingerprint != nil },
                                           by: { items[$0].identityFingerprint! })
        for group in fingerprintGroups.values where group.count > 1 {
            record(.duplicateIdentity, group, "Multiple inventory entries share the same binary identity fingerprint.")
        }

        let installGroups = Dictionary(grouping: items.indices.compactMap { index -> (Int, String)? in
            guard let name = items[index].machOInstallName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !name.isEmpty,
                  items[index].identityFingerprint != nil else { return nil }
            return (index, name)
        }, by: { $0.1 })
        for group in installGroups.values {
            let indices = group.map { $0.0 }
            let fingerprints = Set(indices.compactMap { items[$0].identityFingerprint })
            if indices.count > 1 && fingerprints.count > 1 {
                record(.installNameCollision, indices, "The same install name is used by binaries with different UUID/CDHash fingerprints; possible fork or rebuild.")
            }
        }

        let uuidGroups = Dictionary(grouping: items.indices.flatMap { index -> [(Int, String)] in
            let values = items[index].machOUUIDs.isEmpty ? (items[index].machOUUID.map { [$0] } ?? []) : items[index].machOUUIDs
            return normalized(values).map { (index, $0) }
        }, by: { $0.1 })
        for group in uuidGroups.values {
            let indices = Array(Set(group.map { $0.0 })).sorted()
            let hashes = Set(indices.flatMap { normalized(items[$0].machOCDHashes) })
            if indices.count > 1 && hashes.count > 1 {
                record(.uuidCDHashMismatch, indices, "The same Mach-O UUID is associated with different CDHashes.")
            }
        }
        return Analysis(items: items, conflicts: conflicts.sorted { $0.id < $1.id })
    }

    static func fingerprint(installNames: [String], uuids: [String], cdHashes: [String],
                            architectures: [String] = []) -> String? {
        func normalize(_ values: [String]) -> [String] {
            Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted()
        }
        let names = normalize(installNames)
        let normalizedUUIDs = normalize(uuids)
        let hashes = normalize(cdHashes)
        let archs = normalize(architectures)
        guard !normalizedUUIDs.isEmpty || !hashes.isEmpty else { return nil }
        let components = [
            names.isEmpty ? nil : "install=\(names.joined(separator: ","))",
            normalizedUUIDs.isEmpty ? nil : "uuid=\(normalizedUUIDs.joined(separator: ","))",
            hashes.isEmpty ? nil : "cdhash=\(hashes.joined(separator: ","))",
            archs.isEmpty ? nil : "arch=\(archs.joined(separator: ","))"
        ].compactMap { $0 }
        return SHA256Digest.hex(Data(components.joined(separator: "|").utf8))
    }

    private func normalized(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted()
    }
}
