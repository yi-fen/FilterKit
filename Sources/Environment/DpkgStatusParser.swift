import Foundation

enum DpkgStatusParser {
    static func elleKitStanzas(in text: String) -> [[String: String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { paragraph in
            var fields: [String: String] = [:]
            var currentKey: String?
            for rawLine in paragraph.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                if rawLine.isEmpty { continue }
                if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") {
                    guard let key = currentKey else { continue }
                    let continuation = String(rawLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                    fields[key, default: ""] += "\n" + continuation
                    continue
                }
                guard let separator = rawLine.firstIndex(of: ":") else { currentKey = nil; continue }
                let key = String(rawLine[..<separator])
                let value = rawLine[rawLine.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                fields[key] = value
                currentKey = key
            }
            return fields["Package"] == "ellekit" ? fields : nil
        }
    }

    static func installedMetadata(in text: String, sourcePath: String,
                                  isCurrentStatusDatabase: Bool) -> ElleKitPackageMetadata? {
        let installed = elleKitStanzas(in: text).filter { $0["Status"] == "install ok installed" }
        guard installed.count == 1, let stanza = installed.first else { return nil }
        return ElleKitPackageMetadata(package: "ellekit", version: stanza["Version"],
                                      architecture: stanza["Architecture"], status: stanza["Status"],
                                      maintainer: stanza["Maintainer"], origin: stanza["Origin"],
                                      homepage: stanza["Homepage"], sourcePath: sourcePath,
                                      isCurrentStatusDatabase: isCurrentStatusDatabase)
    }
}
