import Foundation

struct AppBinaryIdentitySnapshot: Equatable {
    let bundleIdentifier: String
    let executableName: String
    let slices: [MachOSliceMetadata]
    let sha256: String

    static func inspectMainBundle(bundle: Bundle = .main,
                                  fileManager: FileManager = .default) -> AppBinaryIdentitySnapshot? {
        guard let executableURL = bundle.executableURL,
              let attributes = try? fileManager.attributesOfItem(atPath: executableURL.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size > 0, size <= 256 * 1024 * 1024,
              let data = try? Data(contentsOf: executableURL, options: .mappedIfSafe),
              let slices = try? MachOMetadataReader().readSlices(data: data), !slices.isEmpty else { return nil }
        return AppBinaryIdentitySnapshot(bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            executableName: executableURL.lastPathComponent, slices: slices,
            sha256: SHA256Digest.hex(data))
    }
}
