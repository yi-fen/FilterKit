import Foundation
import ZIPFoundation

/// Read-only ZIP package inspection for P2-40-R2.
/// Entries are extracted into memory only after path/type/size checks; no archive path is written to disk.
struct PluginZIPArchiveInspector {
    struct Plugin {
        let archivePath: String
        let inspection: PluginImportInspection
        let matchedPlistArchivePath: String?
    }

    struct Result {
        let plugins: [Plugin]
        let ignoredFiles: [String]
        let warnings: [String]
    }

    enum InspectionError: LocalizedError {
        case invalidArchive
        case tooManyEntries
        case unsafeEntry(String)
        case unsupportedEntryType(String)
        case entryTooLarge(String)
        case archiveTooLarge
        case suspiciousCompressionRatio(String)
        case noDylibs
        case ambiguousPlist(dylib: String, candidates: [String])
        case duplicateDylibNames([String])

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "The selected ZIP file is invalid or cannot be opened."
            case .tooManyEntries: return "The ZIP contains more than 512 entries."
            case .unsafeEntry(let path): return "The ZIP contains an unsafe path: \(path)"
            case .unsupportedEntryType(let path): return "The ZIP contains an unsupported symbolic link or special entry: \(path)"
            case .entryTooLarge(let path): return "The ZIP entry exceeds the 256 MiB limit: \(path)"
            case .archiveTooLarge: return "The expanded ZIP contents exceed the 512 MiB limit."
            case .suspiciousCompressionRatio(let path): return "The ZIP entry has a suspicious compression ratio: \(path)"
            case .noDylibs: return "No .dylib plugin was found in the ZIP package."
            case .ambiguousPlist(let dylib, let candidates): return "Multiple plist files could match \(dylib): \(candidates.joined(separator: ", "))."
            case .duplicateDylibNames(let names): return "The ZIP contains duplicate dylib filenames: \(names.joined(separator: ", "))."
            }
        }
    }

    private struct ExtractedEntry {
        let path: String
        let data: Data
    }

    private let maximumEntries = 512
    private let maximumEntryBytes = 256 * 1024 * 1024
    private let maximumExpandedBytes = 512 * 1024 * 1024

    func inspect(archiveURL: URL, targetBundleIdentifier: String) throws -> Result {
        guard PluginImportInspector.isValidBundleIdentifier(targetBundleIdentifier),
              archiveURL.pathExtension.lowercased() == "zip",
              let values = try? archiveURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let archiveSize = values.fileSize, archiveSize > 0,
              archiveSize <= maximumExpandedBytes else {
            throw InspectionError.invalidArchive
        }
        let archive: Archive
        do { archive = try Archive(url: archiveURL, accessMode: .read) }
        catch { throw InspectionError.invalidArchive }
        var entries: [ExtractedEntry] = []
        var expandedTotal = 0
        var scannedEntryCount = 0
        var seenPaths = Set<String>()

        for entry in archive {
            scannedEntryCount += 1
            guard scannedEntryCount <= maximumEntries else { throw InspectionError.tooManyEntries }
            let rawPath = entry.path
            let path = entry.type == .directory ? rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath : rawPath
            guard Self.isSafeRelativePath(path) else { throw InspectionError.unsafeEntry(rawPath) }
            switch entry.type {
            case .directory:
                continue
            case .file:
                break
            default:
                throw InspectionError.unsupportedEntryType(path)
            }
            guard seenPaths.insert(path).inserted else { throw InspectionError.unsafeEntry(path) }
            let expandedSize = Int(entry.uncompressedSize)
            let compressedSize = max(1, Int(entry.compressedSize))
            guard expandedSize <= maximumEntryBytes else { throw InspectionError.entryTooLarge(path) }
            expandedTotal += expandedSize
            guard expandedTotal <= maximumExpandedBytes else { throw InspectionError.archiveTooLarge }
            if expandedSize > 10 * 1024 * 1024 && expandedSize / compressedSize > 100 {
                throw InspectionError.suspiciousCompressionRatio(path)
            }

            var data = Data()
            var exceededLimit = false
            do {
                _ = try archive.extract(entry, consumer: { chunk in
                    if data.count + chunk.count > maximumEntryBytes ||
                        expandedTotal - expandedSize + data.count + chunk.count > maximumExpandedBytes {
                        exceededLimit = true
                        return
                    }
                    data.append(chunk)
                })
            } catch {
                throw InspectionError.invalidArchive
            }
            if exceededLimit { throw InspectionError.entryTooLarge(path) }
            guard data.count == expandedSize else { throw InspectionError.invalidArchive }
            entries.append(ExtractedEntry(path: path, data: data))
        }

        let dylibs = entries.filter { URL(fileURLWithPath: $0.path).pathExtension.lowercased() == "dylib" }
        guard !dylibs.isEmpty else { throw InspectionError.noDylibs }
        let duplicateNames = Dictionary(grouping: dylibs, by: { URL(fileURLWithPath: $0.path).lastPathComponent })
            .filter { $0.value.count > 1 }.map(\.key).sorted()
        guard duplicateNames.isEmpty else { throw InspectionError.duplicateDylibNames(duplicateNames) }

        var plugins: [Plugin] = []
        for dylib in dylibs {
            let parent = URL(fileURLWithPath: dylib.path).deletingLastPathComponent().path
            let basename = URL(fileURLWithPath: dylib.path).deletingPathExtension().lastPathComponent
            let candidates = entries.filter { item in
                let url = URL(fileURLWithPath: item.path)
                guard url.deletingLastPathComponent().path == parent,
                      url.pathExtension.lowercased() == "plist" else { return false }
                return url.lastPathComponent == "Filter.plist" || url.lastPathComponent == "\(basename).plist"
            }
            guard candidates.count <= 1 else {
                throw InspectionError.ambiguousPlist(dylib: dylib.path, candidates: candidates.map(\.path).sorted())
            }
            let matched = candidates.first
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FilterKit-ZIP-Inspection-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
            let dylibURL = tempDirectory.appendingPathComponent(URL(fileURLWithPath: dylib.path).lastPathComponent)
            try dylib.data.write(to: dylibURL, options: .atomic)
            var plistURL: URL?
            if let matched {
                let url = tempDirectory.appendingPathComponent(matched.path.split(separator: "/").last.map(String.init) ?? "Filter.plist")
                try matched.data.write(to: url, options: .atomic)
                plistURL = url
            }
            let inspection = try PluginImportInspector().inspect(
                dylibURL: dylibURL, originalPlistURL: plistURL,
                targetBundleIdentifier: targetBundleIdentifier)
            plugins.append(Plugin(archivePath: dylib.path, inspection: inspection,
                                  matchedPlistArchivePath: matched?.path))
        }

        let consumed = Set(dylibs.map(\.path) + plugins.compactMap(\.matchedPlistArchivePath))
        let ignored = entries.map(\.path).filter { !consumed.contains($0) }.sorted()
        var warnings: [String] = []
        if dylibs.count > 1 { warnings.append("The ZIP contains \(dylibs.count) dylib plugins. Each plugin will be reviewed separately; all belong to the same import batch.") }
        if !ignored.isEmpty { warnings.append("Non-plugin files were not imported: \(ignored.prefix(12).joined(separator: ", "))") }
        return Result(plugins: plugins, ignoredFiles: ignored, warnings: warnings)
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
