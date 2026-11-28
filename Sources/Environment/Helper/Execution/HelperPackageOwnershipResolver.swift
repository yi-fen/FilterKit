import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Helper-side read-only dpkg ownership lookup. It scans only explicitly configured dpkg
/// info directories and never invokes dpkg or changes package-manager state.
struct HelperPackageOwnershipResolver {
    enum ResolutionError: Error, Equatable { case notRoot, invalidPath, noDatabase, unsafeDatabase, readFailed }

    func resolve(pluginDirectory: String, fileNames: [String], infoDirectories: [String]) throws -> HelperPackageOwnershipProof {
        guard geteuid() == 0 else { throw ResolutionError.notRoot }
        guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory), pluginDirectory != "/",
              !fileNames.isEmpty, fileNames.allSatisfy(HelperPolicy.isSafeLeafName),
              !infoDirectories.isEmpty, infoDirectories.allSatisfy({ HelperPolicy.isAbsoluteCleanPath($0) }) else {
            throw ResolutionError.invalidPath
        }
        let targets = Set(fileNames.map { pluginDirectory + "/" + $0 })
        var scannedAny = false
        var databaseEvidence: [String] = []
        for path in Set(infoDirectories).sorted() {
            let dirFD = try openDirectoryIfPresent(path)
            guard let dirFD else { continue }
            defer { _ = close(dirFD) }
            try validateDatabaseDirectory(dirFD)
            scannedAny = true
            let duplicateFD = dup(dirFD)
            guard duplicateFD >= 0, let stream = fdopendir(duplicateFD) else {
                if duplicateFD >= 0 { _ = close(duplicateFD) }
                throw ResolutionError.readFailed
            }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
                }
                guard name.hasSuffix(".list"), HelperPolicy.isSafeLeafName(name) else { continue }
                let data = try readRootFile(dirFD, name: name, maximumBytes: 4 * 1024 * 1024)
                let lines = data.split(separator: 0x0a).compactMap { String(data: $0, encoding: .utf8) }
                if lines.contains(where: { targets.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                    throw HelperPackageOwnershipProof.ProofError.packageOwned
                }
                databaseEvidence.append(path + "/" + name + ":" + SHA256Digest.hex(data))
            }
        }
        guard scannedAny else { throw ResolutionError.noDatabase }
        let digest = SHA256Digest.hex(Data(databaseEvidence.sorted().joined(separator: "\n").utf8))
        return try HelperPackageOwnershipProof(pluginDirectory: pluginDirectory, targetFileNames: fileNames,
            databaseDirectories: infoDirectories, databaseEvidenceSHA256: digest)
    }

    /// Checks whether any dpkg-owned dylib in the managed injection directory already has
    /// the candidate bytes. This is the Helper-side final duplicate guard; the App inventory
    /// preview is advisory and cannot close the time-of-check/time-of-use window by itself.
    func containsPackageManagedDylibSHA256(pluginDirectory: String, expectedSHA256: String,
                                           infoDirectories: [String], maximumBytes: Int = 64 * 1024 * 1024) throws -> Bool {
        guard geteuid() == 0 else { throw ResolutionError.notRoot }
        guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory), pluginDirectory != "/",
              HelperPolicy.isValidHash(expectedSHA256), !infoDirectories.isEmpty,
              infoDirectories.allSatisfy({ HelperPolicy.isAbsoluteCleanPath($0) }) else {
            throw ResolutionError.invalidPath
        }
        guard let pluginFD = try openDirectoryIfPresent(pluginDirectory) else { return false }
        defer { _ = close(pluginFD) }
        try validatePluginDirectory(pluginFD)

        var scannedAny = false
        for infoPath in Set(infoDirectories).sorted() {
            guard let infoFD = try openDirectoryIfPresent(infoPath) else { continue }
            defer { _ = close(infoFD) }
            try validateDatabaseDirectory(infoFD)
            scannedAny = true
            let duplicateFD = dup(infoFD)
            guard duplicateFD >= 0, let stream = fdopendir(duplicateFD) else {
                if duplicateFD >= 0 { _ = close(duplicateFD) }
                throw ResolutionError.readFailed
            }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
                }
                guard name.hasSuffix(".list"), HelperPolicy.isSafeLeafName(name) else { continue }
                let data = try readRootFile(infoFD, name: name, maximumBytes: 4 * 1024 * 1024)
                for rawLine in data.split(separator: 0x0a) {
                    guard let path = String(data: rawLine, encoding: .utf8) else { continue }
                    let prefix = pluginDirectory.hasSuffix("/") ? pluginDirectory : pluginDirectory + "/"
                    guard path.hasPrefix(prefix) else { continue }
                    let leaf = String(path.dropFirst(prefix.count))
                    guard leaf.lowercased().hasSuffix(".dylib"), HelperPolicy.isSafeLeafName(leaf) else { continue }
                    let fd = leaf.withCString { openat(pluginFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
                    if fd < 0 {
                        if errno == ENOENT { continue }
                        throw ResolutionError.readFailed
                    }
                    defer { _ = close(fd) }
                    var metadata = stat()
                    guard fstat(fd, &metadata) == 0,
                          (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                          metadata.st_uid == 0, metadata.st_gid == 0,
                          (metadata.st_mode & 0o6022) == 0,
                          metadata.st_size >= 0, metadata.st_size <= maximumBytes else {
                        throw ResolutionError.unsafeDatabase
                    }
                    var bytes = Data(); bytes.reserveCapacity(Int(metadata.st_size))
                    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                    while true {
                        let count = read(fd, &buffer, buffer.count)
                        if count < 0 && errno == EINTR { continue }
                        guard count >= 0 else { throw ResolutionError.readFailed }
                        if count == 0 { break }
                        bytes.append(contentsOf: buffer.prefix(count))
                        guard bytes.count <= maximumBytes else { throw ResolutionError.unsafeDatabase }
                    }
                    if SHA256Digest.hex(bytes).caseInsensitiveCompare(expectedSHA256) == .orderedSame {
                        return true
                    }
                }
            }
        }
        guard scannedAny else { throw ResolutionError.noDatabase }
        return false
    }

    private func validatePluginDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            throw ResolutionError.unsafeDatabase
        }
    }

    private func openDirectoryIfPresent(_ path: String) throws -> Int32? {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ResolutionError.unsafeDatabase }
        for component in path.split(separator: "/").map(String.init) {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            if next < 0 {
                let code = errno
                _ = close(fd)
                if code == ENOENT { return nil }
                throw ResolutionError.unsafeDatabase
            }
            _ = close(fd); fd = next
        }
        return fd
    }

    private func validateDatabaseDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o022) == 0 else {
            throw ResolutionError.unsafeDatabase
        }
    }

    private func readRootFile(_ directoryFD: Int32, name: String, maximumBytes: Int) throws -> Data {
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw ResolutionError.readFailed }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o6022) == 0,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw ResolutionError.unsafeDatabase
        }
        var data = Data(); data.reserveCapacity(Int(info.st_size)); var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw ResolutionError.readFailed }
            if n == 0 { break }
            data.append(contentsOf: buffer.prefix(n))
            guard data.count <= maximumBytes else { throw ResolutionError.unsafeDatabase }
        }
        return data
    }
}

/// Evidence token bound to the exact plugin directory and filenames. Only the Helper-side
/// resolver constructs this value after scanning at least one root-owned dpkg info directory.
struct HelperPackageOwnershipProof: Equatable {
    enum ProofError: Error, Equatable { case packageOwned, evidenceMismatch }
    let pluginDirectory: String
    let targetFileNames: Set<String>
    let databaseDirectories: Set<String>
    let databaseEvidenceSHA256: String
    let resolvedAt: Date

    fileprivate init(pluginDirectory: String, targetFileNames: [String], databaseDirectories: [String],
                     databaseEvidenceSHA256: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(pluginDirectory),
              !targetFileNames.isEmpty, targetFileNames.allSatisfy(HelperPolicy.isSafeLeafName),
              !databaseDirectories.isEmpty, HelperPolicy.isValidHash(databaseEvidenceSHA256) else {
            throw ProofError.evidenceMismatch
        }
        self.pluginDirectory = pluginDirectory
        self.targetFileNames = Set(targetFileNames)
        self.databaseDirectories = Set(databaseDirectories)
        self.databaseEvidenceSHA256 = databaseEvidenceSHA256
        self.resolvedAt = Date()
    }

    func validates(directory: String, fileNames: [String], now: Date = Date()) -> Bool {
        pluginDirectory == directory && targetFileNames == Set(fileNames) &&
            databaseDirectories.isEmpty == false && HelperPolicy.isValidHash(databaseEvidenceSHA256) &&
            abs(now.timeIntervalSince(resolvedAt)) <= 30
    }
}
