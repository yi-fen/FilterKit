import Foundation

enum ContainerDirectoryAppScannerIconBuilder {
    static func make(plist: [String: Any], bundleURL: URL?) -> AppIconDescriptor? {
        guard let bundleURL else { return nil }
        var names: [String] = []
        if let icons = plist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] { names = files }
        if names.isEmpty { names = plist["CFBundleIconFiles"] as? [String] ?? [] }
        if names.isEmpty, let legacy = plist["CFBundleIconFile"] as? String { names = [legacy] }
        let candidates = names.flatMap { name in
            ["", "@3x", "@2x", "-Large", "-Small"].map { suffix in
                let candidate = bundleURL.appendingPathComponent(name + suffix)
                return candidate.pathExtension.isEmpty ? candidate.appendingPathExtension("png") : candidate
            }
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
        let nestedAsset = ((plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] as? String
        let asset = nestedAsset ?? plist["CFBundleIconName"] as? String
        guard !candidates.isEmpty || asset != nil else { return nil }
        return AppIconDescriptor(fileCandidates: candidates, assetName: asset, bundleURL: bundleURL)
    }
}
