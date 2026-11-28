import Foundation

/// Read-only result for the first import stage. No filesystem mutation or Helper call occurs here.
struct PluginImportInspection {
    let dylibFileName: String
    let dylibSHA256: String
    let architectures: [String]
    let installName: String?
    let currentVersion: String?
    let compatibilityVersion: String?
    let codeSignatureStates: [String]
    let originalPlistFileName: String?
    let originalPlistSHA256: String?
    let generatedPlist: Data?
    let displayName: String
    let author: String?
    let version: String?
    let warnings: [String]

    var usesGeneratedPlist: Bool { originalPlistFileName == nil && generatedPlist != nil }
}

enum PluginImportInspectionError: LocalizedError {
    case dylibTooLarge
    case emptyDylib
    case invalidMachO
    case plistTooLarge
    case invalidPlist
    case targetBundleIdentifierInvalid

    var errorDescription: String? {
        switch self {
        case .dylibTooLarge: return "The dylib exceeds the 256 MiB inspection limit."
        case .emptyDylib: return "The selected dylib is empty."
        case .invalidMachO: return "The selected file is not a valid supported Mach-O binary."
        case .plistTooLarge: return "The selected plist exceeds the 4 MiB inspection limit."
        case .invalidPlist: return "The selected Filter.plist is not a valid property-list dictionary."
        case .targetBundleIdentifierInvalid: return "The target app bundle identifier is invalid."
        }
    }
}

/// Conservative metadata reader and Filter.plist generator for P2-40-R1.
/// Unknown injection semantics (Classes/Executables/Mode) are never guessed.
struct PluginImportInspector {
    private let machOReader = MachOMetadataReader()

    func inspect(dylibURL: URL, originalPlistURL: URL?, targetBundleIdentifier: String) throws -> PluginImportInspection {
        guard Self.isValidBundleIdentifier(targetBundleIdentifier) else {
            throw PluginImportInspectionError.targetBundleIdentifierInvalid
        }
        let dylibValues = try dylibURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard dylibValues.isRegularFile == true, let dylibSize = dylibValues.fileSize, dylibSize > 0 else {
            throw PluginImportInspectionError.emptyDylib
        }
        guard dylibSize <= 256 * 1024 * 1024 else { throw PluginImportInspectionError.dylibTooLarge }
        let dylibData = try Data(contentsOf: dylibURL, options: [.mappedIfSafe])
        guard !dylibData.isEmpty else { throw PluginImportInspectionError.emptyDylib }

        let slices: [MachOSliceMetadata]
        do { slices = try machOReader.readSlices(data: dylibData) }
        catch { throw PluginImportInspectionError.invalidMachO }
        guard !slices.isEmpty else { throw PluginImportInspectionError.invalidMachO }

        var warnings: [String] = []
        let originalPlistData: Data?
        if let originalPlistURL {
            let values = try originalPlistURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 4 * 1024 * 1024 else {
                throw PluginImportInspectionError.plistTooLarge
            }
            let data = try Data(contentsOf: originalPlistURL, options: [.mappedIfSafe])
            guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is [String: Any] else {
                throw PluginImportInspectionError.invalidPlist
            }
            originalPlistData = data
        } else {
            originalPlistData = nil
        }

        let generated: Data?
        if originalPlistData == nil {
            generated = try Self.makeBaseFilterPlist(targetBundleIdentifier: targetBundleIdentifier)
            warnings.append("Filter.plist was not supplied. A minimal Bundles-only configuration was generated; injection rules were not inferred.")
        } else {
            generated = nil
        }

        let plistMetadata = originalPlistData.flatMap(Self.metadata(from:))
        let inferredName = slices.compactMap { $0.codeSignatureIdentifier }.first
            ?? slices.compactMap { $0.installName }.first.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            ?? dylibURL.deletingPathExtension().lastPathComponent
        let displayName = plistMetadata?.name ?? inferredName
        if slices.contains(where: { $0.codeSignatureState != "cdhash_extracted" }) {
            warnings.append("One or more Mach-O slices do not expose an extractable CodeDirectory hash; this is metadata only, not signature trust verification.")
        }
        if !slices.contains(where: { $0.architecture == "arm64" || $0.architecture == "arm64e" }) {
            warnings.append("No arm64/arm64e slice was identified. Device compatibility has not been established.")
        }
        if originalPlistData != nil {
            warnings.append("The supplied plist is preserved byte-for-byte during inspection; its injection semantics require separate review.")
        }

        return PluginImportInspection(
            dylibFileName: dylibURL.lastPathComponent,
            dylibSHA256: SHA256Digest.hex(dylibData),
            architectures: Array(Set(slices.compactMap(\.architecture))).sorted(),
            installName: slices.compactMap(\.installName).first,
            currentVersion: slices.compactMap(\.currentVersion).first,
            compatibilityVersion: slices.compactMap(\.compatibilityVersion).first,
            codeSignatureStates: Array(Set(slices.map(\.codeSignatureState))).sorted(),
            originalPlistFileName: originalPlistURL?.lastPathComponent,
            originalPlistSHA256: originalPlistData.map(SHA256Digest.hex),
            generatedPlist: generated,
            displayName: displayName,
            author: plistMetadata?.author,
            version: plistMetadata?.version ?? slices.compactMap(\.currentVersion).first,
            warnings: warnings
        )
    }

    static func makeBaseFilterPlist(targetBundleIdentifier: String) throws -> Data {
        guard isValidBundleIdentifier(targetBundleIdentifier) else {
            throw PluginImportInspectionError.targetBundleIdentifierInvalid
        }
        let root: [String: Any] = ["Filter": ["Bundles": [targetBundleIdentifier]]]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isLetter || first.isNumber || first == "_" else { return false }
            return part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }
    }

    private struct PlistMetadata {
        let name: String?
        let author: String?
        let version: String?
    }

    private static func metadata(from data: Data) -> PlistMetadata? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        func firstString(_ keys: [String]) -> String? {
            for key in keys {
                if let value = root[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            }
            return nil
        }
        return PlistMetadata(name: firstString(["Name", "name", "CFBundleName", "FilterName"]),
                             author: firstString(["Author", "author", "Maintainer"]),
                             version: firstString(["Version", "version", "CFBundleShortVersionString"]))
    }
}
