import Foundation

/// Read-only dpkg ownership lookup. Reads status and info/*.list files; never invokes dpkg/APT
/// and never modifies package-manager state.
final class DpkgFileOwnershipProvider: PackageOwnershipProviding {
    private let fileManager: FileManager
    private let databaseRoots: [URL]

    init(jbroot: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        let target = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        for root in databaseRoots {
            let dpkg = root.appendingPathComponent("var/lib/dpkg", isDirectory: true)
            let statusURL = dpkg.appendingPathComponent("status")
            guard let status = try? String(contentsOf: statusURL, encoding: .utf8) else { continue }
            // Match R16's first-readable-status rule: do not mix ownership evidence
            // from multiple roots/databases.
            let packages = Self.installedPackages(in: status)
            let info = dpkg.appendingPathComponent("info", isDirectory: true)
            for package in packages {
                let listURL = info.appendingPathComponent(package.name + ".list")
                guard let contents = try? String(contentsOf: listURL, encoding: .utf8) else { continue }
                for raw in contents.split(whereSeparator: \.isNewline) {
                    let entry = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !entry.isEmpty else { continue }
                    let listed = URL(fileURLWithPath: entry).standardizedFileURL.resolvingSymlinksInPath().path
                    if listed == target {
                        return PackageOwnershipEvidence(isOwnedByPackage: true,
                            packageIdentifier: package.name, evidenceSource: "dpkg-info-list", packageVersion: package.version)
                    }
                }
            }
            return PackageOwnershipEvidence(isOwnedByPackage: false, packageIdentifier: nil,
                evidenceSource: "dpkg-status-readable-no-file-owner")
        }
        return PackageOwnershipEvidence(isOwnedByPackage: false, packageIdentifier: nil,
            evidenceSource: "dpkg-status-unavailable")
    }

    private static func installedPackages(in text: String) -> [(name: String, version: String?)] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { stanza in
            var fields: [String: String] = [:]
            for line in stanza.split(separator: "\n") {
                guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { continue }
                fields[String(line[..<colon])] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            guard fields["Status"] == "install ok installed" else { return nil }
            guard let name = fields["Package"] else { return nil }
            return (name, fields["Version"])
        }
    }
}
