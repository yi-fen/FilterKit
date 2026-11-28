import Foundation

/// Resolves an optional Filter.plist for a selected dylib without guessing among unrelated files.
/// Only conventional sibling names are considered; archive/package traversal is handled by later import stages.
struct PluginImportFilePairResolver {
    enum ResolutionError: LocalizedError {
        case invalidDylib
        case invalidExplicitPlist
        case ambiguousSiblingPlists([String])
        case symbolicLinkNotAllowed

        var errorDescription: String? {
            switch self {
            case .invalidDylib: return "Select a regular .dylib file."
            case .invalidExplicitPlist: return "The selected Filter.plist must be a regular .plist file."
            case .ambiguousSiblingPlists(let names):
                return "More than one matching plist was found: \(names.joined(separator: ", ")). Select the correct plist explicitly."
            case .symbolicLinkNotAllowed: return "Symbolic links are not accepted as plugin import files."
            }
        }
    }

    /// Explicit selection wins. Otherwise auto-matches `<dylib-name>.plist` or `Filter.plist` in the same directory.
    /// If both exist, the dylib-specific name wins only when it is the sole candidate; ambiguity is surfaced.
    func resolve(dylibURL: URL, explicitlySelectedPlistURL: URL? = nil,
                 fileManager: FileManager = .default) throws -> URL? {
        guard dylibURL.pathExtension.lowercased() == "dylib",
              Self.isRegularNonSymlinkFile(dylibURL, fileManager: fileManager) else {
            throw ResolutionError.invalidDylib
        }
        if let explicitlySelectedPlistURL {
            guard explicitlySelectedPlistURL.pathExtension.lowercased() == "plist",
                  Self.isRegularNonSymlinkFile(explicitlySelectedPlistURL, fileManager: fileManager) else {
                throw ResolutionError.invalidExplicitPlist
            }
            return explicitlySelectedPlistURL
        }

        let directory = dylibURL.deletingLastPathComponent()
        let baseName = dylibURL.deletingPathExtension().lastPathComponent
        let candidateNames = ["\(baseName).plist", "Filter.plist"]
        let candidates = candidateNames.map { directory.appendingPathComponent($0) }
            .filter { Self.isRegularNonSymlinkFile($0, fileManager: fileManager) }
        let unique = Dictionary(grouping: candidates, by: { $0.standardizedFileURL.path }).compactMap { $0.value.first }
        guard unique.count <= 1 else {
            throw ResolutionError.ambiguousSiblingPlists(unique.map(\.lastPathComponent).sorted())
        }
        return unique.first
    }

    private static func isRegularNonSymlinkFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return false }
        return true
    }
}
