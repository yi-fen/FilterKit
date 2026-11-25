import Foundation

/// Read-only dpkg ownership index. Mirrors R16's status + info/*.list evidence,
/// but indexes the database once per scan instead of reopening every package list
/// for every dylib/plist. It never invokes dpkg/APT and never modifies package state.
final class DpkgFileOwnershipProvider: PackageOwnershipProviding {
    private struct PackageRecord {
        let identifier: String
        let version: String?
    }

    private struct Index {
        let statusWasReadable: Bool
        let ownersByPath: [String: PackageRecord]
    }

    private let databaseRoots: [URL]
    private let lock = NSLock()
    private var cachedIndex: Index?

    init(jbroot: String) {
        let roots = [
            URL(fileURLWithPath: jbroot, isDirectory: true),
            URL(fileURLWithPath: "/var/jb", isDirectory: true),
            URL(fileURLWithPath: "/var/rootless", isDirectory: true),
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
        var seen = Set<String>()
        self.databaseRoots = roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    func ownershipEvidence(for fileURL: URL) throws -> PackageOwnershipEvidence {
        let index = loadIndex()
        let keys = pathKeys(for: fileURL)
        for key in keys {
            if let owner = index.ownersByPath[key] {
                return PackageOwnershipEvidence(isOwnedByPackage: true,
                    packageIdentifier: owner.identifier, evidenceSource: "dpkg-info-list",
                    packageVersion: owner.version)
            }
        }
        return PackageOwnershipEvidence(isOwnedByPackage: false, packageIdentifier: nil,
            evidenceSource: index.statusWasReadable ? "dpkg-status-readable-no-file-owner" : "dpkg-status-unavailable")
    }

    private func loadIndex() -> Index {
        lock.lock()
        if let cachedIndex { lock.unlock(); return cachedIndex }
        lock.unlock()

        var built = Index(statusWasReadable: false, ownersByPath: [:])
        // R16 rule: use the first readable dpkg status database; never mix roots.
        for root in databaseRoots {
            let dpkg = root.appendingPathComponent("var/lib/dpkg", isDirectory: true)
            let statusURL = dpkg.appendingPathComponent("status")
            guard let status = try? String(contentsOf: statusURL, encoding: .utf8) else { continue }
            let packages = Self.installedPackages(in: status)
            let info = dpkg.appendingPathComponent("info", isDirectory: true)
            var owners: [String: PackageRecord] = [:]
            for package in packages {
                let listURL = info.appendingPathComponent(package.identifier + ".list")
                guard let contents = try? String(contentsOf: listURL, encoding: .utf8) else { continue }
                let record = PackageRecord(identifier: package.identifier, version: package.version)
                for raw in contents.split(whereSeparator: \.isNewline) {
                    let entry = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !entry.isEmpty, entry.hasPrefix("/") else { continue }
                    for key in Self.logicalPathKeys(entry, databaseRoot: root) {
                        // Keep the first owner deterministically; multiple-owner
                        // conflicts are separately guarded by the higher-level scan.
                        if owners[key] == nil { owners[key] = record }
                    }
                }
            }
            built = Index(statusWasReadable: true, ownersByPath: owners)
            break
        }

        lock.lock()
        if cachedIndex == nil { cachedIndex = built }
        let result = cachedIndex ?? built
        lock.unlock()
        return result
    }

    private func pathKeys(for fileURL: URL) -> [String] {
        var keys = Set<String>()
        let raw = fileURL.standardizedFileURL.path
        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        for path in [raw, resolved] {
            keys.formUnion(Self.logicalPathKeys(path, databaseRoot: nil))
            for root in databaseRoots {
                keys.formUnion(Self.logicalPathKeys(path, databaseRoot: root))
                let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
                keys.formUnion(Self.logicalPathKeys(path, databaseRoot: resolvedRoot))
            }
        }
        return Array(keys)
    }

    private static func logicalPathKeys(_ path: String, databaseRoot: URL?) -> Set<String> {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        var keys: Set<String> = [standardized]
        if standardized == "/var/jb" { keys.insert("/") }
        if standardized.hasPrefix("/var/jb/") {
            keys.insert(String(standardized.dropFirst("/var/jb".count)))
        }
        if let databaseRoot {
            let rootPath = databaseRoot.standardizedFileURL.path
            if rootPath != "/", standardized.hasPrefix(rootPath + "/") {
                keys.insert("/" + standardized.dropFirst(rootPath.count + 1))
            }
        }
        return Set(keys.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    private static func installedPackages(in text: String) -> [(identifier: String, version: String?)] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { stanza in
            var fields: [String: String] = [:]
            var currentKey: String?
            for line in stanza.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                if line.isEmpty { continue }
                if line.hasPrefix(" ") || line.hasPrefix("\t") {
                    if let currentKey { fields[currentKey, default: ""] += "\n" + line.trimmingCharacters(in: .whitespaces) }
                    continue
                }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[..<colon])
                fields[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                currentKey = key
            }
            guard fields["Status"]?.contains(" installed") == true,
                  let identifier = fields["Package"], !identifier.isEmpty,
                  !identifier.contains("/"), !identifier.contains("..") else { return nil }
            return (identifier, fields["Version"])
        }
    }
}
