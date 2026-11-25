import Foundation

enum ContainerDirectoryAppScannerIconBuilder {
    static func make(plist: [String: Any], bundleURL: URL?) -> AppIconDescriptor? {
        guard let bundleURL else { return nil }
        let primary = ((plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]) ?? [:]
        var names = primary["CFBundleIconFiles"] as? [String] ?? []
        if names.isEmpty { names = plist["CFBundleIconFiles"] as? [String] ?? [] }
        if names.isEmpty, let legacy = plist["CFBundleIconFile"] as? String { names = [legacy] }

        // R16's loader tried the literal CFBundleIconFiles path first, then the
        // common PNG/JPEG scale variants. Keep candidates even when fileExists
        // cannot see a protected bundle resource; UIKit gets the final read attempt.
        var candidates: [URL] = []
        for name in names {
            let variants = Self.fileNameVariants(for: name)
            for base in [bundleURL, bundleURL.appendingPathComponent("Resources", isDirectory: true)] {
                candidates.append(contentsOf: variants.map { base.appendingPathComponent($0) })
            }
        }
        candidates = Array(Set(candidates)).sorted { lhs, rhs in
            Self.candidateRank(lhs.lastPathComponent) < Self.candidateRank(rhs.lastPathComponent)
        }

        let asset = (primary["CFBundleIconName"] as? String)
            ?? (plist["CFBundleIconName"] as? String)
        guard !candidates.isEmpty || asset != nil else { return nil }
        return AppIconDescriptor(fileCandidates: candidates, assetName: asset, bundleURL: bundleURL)
    }

    private static func fileNameVariants(for rawName: String) -> [String] {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        let extensions = ext.isEmpty ? ["", ".png", ".jpg", ".jpeg"] : ["", ".png", ".jpg", ".jpeg"]
        var output: [String] = [name]
        for scale in ["@3x", "@2x", ""] {
            for suffix in extensions {
                let candidate = stem + scale + suffix
                if !output.contains(candidate) { output.append(candidate) }
            }
        }
        return output
    }

    private static func candidateRank(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("@3x") { return 0 }
        if lower.contains("@2x") { return 1 }
        return 2
    }
}
