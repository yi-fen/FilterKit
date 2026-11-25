import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Optional runtime libroot discovery. It uses dlopen/dlsym and has no link-time
/// dependency on libroot, keeping ordinary Xcode builds and offline tests viable.
final class LibrootRuntimeProbe {
    typealias PrefixFunction = @convention(c) () -> UnsafePointer<CChar>?

    private let candidateLibraryPaths: [String]

    init(candidateLibraryPaths: [String] = [
        "/usr/lib/libroot.dylib",
        "/var/jb/usr/lib/libroot.dylib",
        "/private/var/jb/usr/lib/libroot.dylib"
    ]) {
        self.candidateLibraryPaths = candidateLibraryPaths
    }

    func inspect() -> LibrootPathEvidence {
        #if canImport(Darwin)
        // R16 FastPluginInventoryEngine first asks the already-loaded RootHide
        // runtime for jbroot(). Some RootHide builds export this symbol without
        // exposing libroot_get_jbroot_prefix at the expected dylib paths.
        if let processRoot = processJBRoot(), let valid = Self.validAbsolutePath(processRoot) {
            return LibrootPathEvidence(libraryPath: "RTLD_DEFAULT:jbroot", jbrootPrefix: valid,
                rootPrefix: nil, bootUUID: nil, loaded: true, diagnosticCode: "roothide.jbroot_symbol_observed")
        }
        for path in candidateLibraryPaths {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { continue }
            defer { dlclose(handle) }
            guard let jbrootFn = symbol("libroot_get_jbroot_prefix", in: handle),
                  let rootfsFn = symbol("libroot_get_root_prefix", in: handle) else { continue }
            let bootFn = symbol("libroot_get_boot_uuid", in: handle)
            let jbroot = jbrootFn()?.stringValue
            let rootfs = rootfsFn()?.stringValue
            let boot = bootFn?()?.stringValue
            let validJBRoot = jbroot.flatMap(Self.validAbsolutePath)
            let validRootFS = rootfs.flatMap(Self.validAbsolutePath)
            guard let validJBRoot else { continue }
            return LibrootPathEvidence(libraryPath: path, jbrootPrefix: validJBRoot,
                rootPrefix: validRootFS, bootUUID: boot, loaded: true,
                diagnosticCode: validRootFS == nil ? "libroot.rootfs_unavailable" : "libroot.api_observed")
        }
        #endif
        return LibrootPathEvidence(libraryPath: nil, jbrootPrefix: nil, rootPrefix: nil,
            bootUUID: nil, loaded: false, diagnosticCode: "libroot.unavailable_fallback_required")
    }

    #if canImport(Darwin)
    private func processJBRoot() -> String? {
        guard let processHandle = UnsafeMutableRawPointer(bitPattern: -2),
              let raw = dlsym(processHandle, "jbroot") else { return nil }
        typealias JBRootFunction = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
        let function = unsafeBitCast(raw, to: JBRootFunction.self)
        guard let value = "/".withCString({ function($0) }) else { return nil }
        return String(validatingUTF8: value)
    }

    private func symbol(_ name: String, in handle: UnsafeMutableRawPointer) -> PrefixFunction? {
        guard let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: PrefixFunction.self)
    }
    #endif

    private static func validAbsolutePath(_ value: String) -> String? {
        guard value.hasPrefix("/"), !value.contains("\0") else { return nil }
        let normalized = URL(fileURLWithPath: value).standardizedFileURL.path
        guard normalized == value || normalized == value.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            return normalized
        }
        return normalized
    }
}

private extension UnsafePointer where Pointee == CChar {
    var stringValue: String? { String(validatingUTF8: self) }
}
