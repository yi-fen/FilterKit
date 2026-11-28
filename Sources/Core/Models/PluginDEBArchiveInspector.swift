import Foundation

/// Read-only Debian package inspector. It parses the ar container and tar members in memory;
/// no package path is extracted to disk. Compressed tar variants are rejected explicitly until
/// a vetted decoder is bundled, rather than being mistaken for corrupt packages.
struct PluginDEBArchiveInspector {
    struct Plugin {
        let archivePath: String
        let inspection: PluginImportInspection
        let matchedPlistArchivePath: String?
    }

    struct Result {
        let packageName: String?
        let packageVersion: String?
        let packageArchitecture: String?
        let maintainer: String?
        let plugins: [Plugin]
        let ignoredFiles: [String]
        let warnings: [String]
    }

    enum InspectionError: LocalizedError {
        case invalidPackage
        case packageTooLarge
        case missingDataArchive
        case missingControlArchive
        case unsupportedCompression(String)
        case malformedArchive
        case tooManyEntries
        case unsafeEntry(String)
        case unsupportedEntryType(String)
        case entryTooLarge(String)
        case expandedPackageTooLarge
        case noDylibs
        case duplicateDylibNames([String])
        case ambiguousPlist(dylib: String, candidates: [String])

        var errorDescription: String? {
            switch self {
            case .invalidPackage: return "The selected file is not a valid Debian (.deb) package."
            case .packageTooLarge: return "The Debian package exceeds the 512 MiB inspection limit."
            case .missingDataArchive: return "The Debian package does not contain data.tar."
            case .missingControlArchive: return "The Debian package does not contain control.tar."
            case .unsupportedCompression(let name): return "The Debian member uses unsupported compression: \(name). This build accepts uncompressed .tar members only."
            case .malformedArchive: return "The Debian ar/tar structure is malformed or truncated."
            case .tooManyEntries: return "The Debian package contains more than 2,048 tar entries."
            case .unsafeEntry(let path): return "The Debian package contains an unsafe path: \(path)"
            case .unsupportedEntryType(let path): return "The Debian package contains a symbolic link, hard link, or special file: \(path)"
            case .entryTooLarge(let path): return "A Debian package entry exceeds the 256 MiB limit: \(path)"
            case .expandedPackageTooLarge: return "The Debian package expands beyond the 512 MiB inspection limit."
            case .noDylibs: return "No .dylib plugin was found in the Debian data archive."
            case .duplicateDylibNames(let names): return "The Debian package contains duplicate dylib filenames: \(names.joined(separator: ", "))."
            case .ambiguousPlist(let dylib, let candidates): return "Multiple plist files could match \(dylib): \(candidates.joined(separator: ", "))."
            }
        }
    }

    struct ArMember { let name: String; let data: Data }
    private struct TarEntry { let path: String; let data: Data; let isDirectory: Bool }
    private let maxPackageBytes = 512 * 1024 * 1024
    private let maxEntryBytes = 256 * 1024 * 1024
    private let maxEntries = 2_048
    private let maxExpandedBytes = 512 * 1024 * 1024

    func inspect(packageURL: URL, targetBundleIdentifier: String) throws -> Result {
        guard PluginImportInspector.isValidBundleIdentifier(targetBundleIdentifier),
              packageURL.pathExtension.lowercased() == "deb",
              let values = try? packageURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw InspectionError.invalidPackage
        }
        guard size <= maxPackageBytes else { throw InspectionError.packageTooLarge }
        let packageData = try Data(contentsOf: packageURL, options: [.mappedIfSafe])
        let members = try Self.parseAr(packageData, maximumMemberBytes: maxPackageBytes)
        guard let debianVersion = members.first(where: { $0.name == "debian-binary" }),
              String(data: debianVersion.data, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) == "2.0" else {
            throw InspectionError.invalidPackage
        }
        guard let controlMember = members.first(where: { $0.name == "control.tar" || $0.name.hasPrefix("control.tar.") }) else {
            throw InspectionError.missingControlArchive
        }
        guard let dataMember = members.first(where: { $0.name == "data.tar" || $0.name.hasPrefix("data.tar.") }) else {
            throw InspectionError.missingDataArchive
        }
        let controlEntries = try parseTarMember(controlMember)
        let dataEntries = try parseTarMember(dataMember)
        let controlText = controlEntries.first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == "control" })
            .flatMap { String(data: $0.data, encoding: .utf8) }
        let control = Self.parseControl(controlText ?? "")

        let dylibs = dataEntries.filter { !$0.isDirectory && URL(fileURLWithPath: $0.path).pathExtension.lowercased() == "dylib" }
        guard !dylibs.isEmpty else { throw InspectionError.noDylibs }
        let duplicateNames = Dictionary(grouping: dylibs, by: { URL(fileURLWithPath: $0.path).lastPathComponent })
            .filter { $0.value.count > 1 }.map(\.key).sorted()
        guard duplicateNames.isEmpty else { throw InspectionError.duplicateDylibNames(duplicateNames) }

        var plugins: [Plugin] = []
        for dylib in dylibs {
            let parent = URL(fileURLWithPath: dylib.path).deletingLastPathComponent().path
            let basename = URL(fileURLWithPath: dylib.path).deletingPathExtension().lastPathComponent
            let candidates = dataEntries.filter { entry in
                guard !entry.isDirectory else { return false }
                let url = URL(fileURLWithPath: entry.path)
                return url.deletingLastPathComponent().path == parent && url.pathExtension.lowercased() == "plist" &&
                    (url.lastPathComponent == "Filter.plist" || url.lastPathComponent == "\(basename).plist")
            }
            guard candidates.count <= 1 else {
                throw InspectionError.ambiguousPlist(dylib: dylib.path, candidates: candidates.map(\.path).sorted())
            }
            let matched = candidates.first
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("FilterKit-DEB-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let dylibURL = temp.appendingPathComponent(URL(fileURLWithPath: dylib.path).lastPathComponent)
            try dylib.data.write(to: dylibURL, options: .atomic)
            var plistURL: URL?
            if let matched {
                let url = temp.appendingPathComponent(URL(fileURLWithPath: matched.path).lastPathComponent)
                try matched.data.write(to: url, options: .atomic)
                plistURL = url
            }
            let inspection = try PluginImportInspector().inspect(dylibURL: dylibURL,
                originalPlistURL: plistURL, targetBundleIdentifier: targetBundleIdentifier)
            plugins.append(Plugin(archivePath: dylib.path, inspection: inspection,
                                  matchedPlistArchivePath: matched?.path))
        }
        let consumed = Set(dylibs.map(\.path) + plugins.compactMap(\.matchedPlistArchivePath))
        let ignored = dataEntries.filter { !$0.isDirectory }.map(\.path).filter { !consumed.contains($0) }.sorted()
        var warnings: [String] = []
        warnings.append("DEB inspection is read-only. Package scripts and maintainer hooks are never executed.")
        if plugins.count > 1 { warnings.append("The Debian package contains \(plugins.count) dylib plugins; they are presented as one import batch.") }
        if !ignored.isEmpty { warnings.append("Non-plugin data files were not imported: \(ignored.prefix(12).joined(separator: ", "))") }
        if control.isEmpty { warnings.append("The control file was missing or could not be decoded; package metadata is unavailable.") }
        return Result(packageName: control["Package"], packageVersion: control["Version"],
                      packageArchitecture: control["Architecture"], maintainer: control["Maintainer"],
                      plugins: plugins, ignoredFiles: ignored, warnings: warnings)
    }

    private func parseTarMember(_ member: ArMember) throws -> [TarEntry] {
        let lower = member.name.lowercased()
        guard lower.hasSuffix(".tar") else { throw InspectionError.unsupportedCompression(member.name) }
        var entries: [TarEntry] = []
        var offset = 0
        var expanded = 0
        var seenPaths = Set<String>()
        while offset + 512 <= member.data.count {
            let header = member.data.subdata(in: offset..<(offset + 512))
            if header.allSatisfy({ $0 == 0 }) { break }
            guard let name = Self.tarString(header, 0, 100), !name.isEmpty,
                  let size = Self.parseTarOctal(header, 124, 12), size <= maxEntryBytes else {
                throw InspectionError.malformedArchive
            }
            let prefix = Self.tarString(header, 345, 155) ?? ""
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            guard Self.isSafeRelativePath(path) else { throw InspectionError.unsafeEntry(path) }
            guard seenPaths.insert(path).inserted else { throw InspectionError.malformedArchive }
            let type = header[156]
            let isDirectory = type == 0x35 || type == 0
            guard isDirectory || type == 0x30 || type == 0x00 else { throw InspectionError.unsupportedEntryType(path) }
            let contentStart = offset + 512
            let paddedSize = ((size + 511) / 512) * 512
            guard contentStart <= member.data.count, paddedSize <= member.data.count - contentStart else {
                throw InspectionError.malformedArchive
            }
            if !isDirectory {
                expanded += size
                guard expanded <= maxExpandedBytes else { throw InspectionError.expandedPackageTooLarge }
                let content = member.data.subdata(in: contentStart..<(contentStart + size))
                entries.append(TarEntry(path: path, data: content, isDirectory: false))
            } else {
                entries.append(TarEntry(path: path, data: Data(), isDirectory: true))
            }
            guard entries.count <= maxEntries else { throw InspectionError.tooManyEntries }
            offset = contentStart + paddedSize
        }
        guard !entries.isEmpty else { throw InspectionError.malformedArchive }
        return entries
    }

    static func parseAr(_ data: Data, maximumMemberBytes: Int = 512 * 1024 * 1024) throws -> [ArMember] {
        let magic = Data("!<arch>\n".utf8)
        guard data.count >= magic.count, data.prefix(magic.count) == magic else { throw InspectionError.invalidPackage }
        var offset = magic.count
        var result: [ArMember] = []
        var gnuStringTable = Data()
        while offset < data.count {
            guard offset + 60 <= data.count else { throw InspectionError.malformedArchive }
            let header = data.subdata(in: offset..<(offset + 60))
            guard String(data: header.subdata(in: 58..<60), encoding: .ascii) == "`\n",
                  let rawName = String(data: header.subdata(in: 0..<16), encoding: .ascii),
                  let rawSize = String(data: header.subdata(in: 48..<58), encoding: .ascii),
                  let size = Int(rawSize.trimmingCharacters(in: .whitespaces)), size >= 0,
                  size <= maximumMemberBytes else { throw InspectionError.malformedArchive }
            let start = offset + 60
            guard start <= data.count, size <= data.count - start else { throw InspectionError.malformedArchive }
            let payload = data.subdata(in: start..<(start + size))
            var name = rawName.trimmingCharacters(in: .whitespaces)
            if name == "//" { gnuStringTable = payload }
            else if name.hasPrefix("/") && name.dropFirst().allSatisfy(\.isNumber),
                    let index = Int(name.dropFirst()), index < gnuStringTable.count {
                let suffix = gnuStringTable.subdata(in: index..<gnuStringTable.count)
                name = (String(data: suffix.prefix { $0 != 0x0A && $0 != 0x00 }, encoding: .utf8) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else if name.hasPrefix("#1/"), let nameLength = Int(name.dropFirst(3)), nameLength <= payload.count {
                name = String(data: payload.prefix(nameLength), encoding: .utf8) ?? ""
                result.append(ArMember(name: name, data: Data(payload.dropFirst(nameLength))))
                offset = start + size + (size % 2)
                continue
            } else { name = name.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            if name != "/" && name != "__.SYMDEF" && !name.isEmpty {
                result.append(ArMember(name: name, data: payload))
            }
            offset = start + size + (size % 2)
        }
        guard !result.isEmpty else { throw InspectionError.malformedArchive }
        return result
    }

    static func parseControl(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty { continue }
            if line.first == " ", let key = currentKey {
                result[key, default: ""] += "\n" + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { currentKey = nil; continue }
            let key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            result[key] = value
            currentKey = key
        }
        return result
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func tarString(_ data: Data, _ offset: Int, _ count: Int) -> String? {
        guard offset + count <= data.count else { return nil }
        let field = data.subdata(in: offset..<(offset + count))
        return String(data: field.prefix { $0 != 0 }, encoding: .utf8)
    }

    private static func parseTarOctal(_ data: Data, _ offset: Int, _ count: Int) -> Int? {
        guard let raw = tarString(data, offset, count) else { return nil }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        if trimmed.isEmpty { return 0 }
        return Int(trimmed, radix: 8)
    }
}
