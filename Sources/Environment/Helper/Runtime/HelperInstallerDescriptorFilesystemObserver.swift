import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Read-only descriptor-relative filesystem inspection. All paths are relative to the already
/// provisioned JBROOT; no path component is followed through a symlink and no mutation is exposed.
struct HelperInstallerDescriptorFilesystemObserver {
    enum ObservationError: Error, Equatable {
        case invalidRoot, invalidRelativePath, openFailed(Int32), rootUnavailable(Int32), unsafeDirectory
        case unsafeFile, oversized, readFailed(Int32), fileChangedDuringRead, decodePointerFailed
    }

    struct FileRecord: Equatable {
        let relativePath: String
        let sha256: String
        let byteCount: Int
        let ownerUID: UInt32
        let groupID: UInt32
        let mode: UInt16
        let device: UInt64
        let inode: UInt64
    }

    struct ReleasePointer: Codable, Equatable {
        let schemaVersion: Int
        let transactionID: UUID
        let releaseIdentifier: String
        let generation: UInt64
        let artifactHashes: [String: String]

        func validate() -> Bool {
            guard schemaVersion == 2, generation > 0,
                  !releaseIdentifier.isEmpty, releaseIdentifier.count <= 128,
                  releaseIdentifier.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil,
                  Set(artifactHashes.keys) == Set(["executable", "deploymentManifest", "launchDaemon"]) else { return false }
            return artifactHashes.values.allSatisfy { $0.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
        }
    }

    private let jbRootPath: String
    private let expectedOwnerUID: UInt32
    private let maximumArtifactBytes: Int
    private let maximumPointerBytes: Int

    init(jbRootPath: String, expectedOwnerUID: UInt32 = 0,
         maximumArtifactBytes: Int = 64 * 1024 * 1024,
         maximumPointerBytes: Int = 16 * 1024) {
        self.jbRootPath = jbRootPath
        self.expectedOwnerUID = expectedOwnerUID
        self.maximumArtifactBytes = max(4096, maximumArtifactBytes)
        self.maximumPointerBytes = max(1024, maximumPointerBytes)
    }

    /// Opens and hashes a regular file through openat descriptors. A stable inode/size/time tuple
    /// is required across the read; callers must still hold the shared installer acceptance lock.
    func observeFile(relativePath: String, privateFile: Bool = false) throws -> FileRecord {
        let components = try validatedComponents(relativePath)
        let rootFD = try openVerifiedRoot()
        defer { _ = close(rootFD) }
        var directoryFD = rootFD
        var ownsDirectoryFD = false
        defer { if ownsDirectoryFD { _ = close(directoryFD) } }
        for component in components.dropLast() {
            let next = component.withCString {
                openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else { throw ObservationError.openFailed(errno) }
            var directoryInfo = stat()
            guard fstat(next, &directoryInfo) == 0,
                  (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  directoryInfo.st_uid == expectedOwnerUID,
                  (directoryInfo.st_mode & 0o022) == 0 else {
                _ = close(next); throw ObservationError.unsafeDirectory
            }
            if ownsDirectoryFD { _ = close(directoryFD) }
            directoryFD = next; ownsDirectoryFD = true
        }
        let leaf = components.last!
        let fd = leaf.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        guard fd >= 0 else { throw ObservationError.openFailed(errno) }
        defer { _ = close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0,
              (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_uid == expectedOwnerUID,
              before.st_nlink == 1,
              (before.st_mode & 0o022) == 0,
              (!privateFile || (before.st_mode & 0o077) == 0) else { throw ObservationError.unsafeFile }
        let limit = privateFile ? maximumPointerBytes : maximumArtifactBytes
        guard before.st_size >= 0, before.st_size <= limit else { throw ObservationError.oversized }
        var data = Data(); data.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while true {
            #if canImport(Darwin)
            let count = Darwin.read(fd, &buffer, buffer.count)
            #elseif canImport(Glibc)
            let count = Glibc.read(fd, &buffer, buffer.count)
            #else
            let count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ObservationError.readFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= limit else { throw ObservationError.oversized }
        }
        var after = stat()
        guard fstat(fd, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              Self.timestampsEqual(before, after),
              data.count == Int(after.st_size) else { throw ObservationError.fileChangedDuringRead }
        return FileRecord(relativePath: relativePath, sha256: SHA256Digest.hex(data),
                          byteCount: data.count, ownerUID: UInt32(before.st_uid),
                          groupID: UInt32(before.st_gid), mode: UInt16(before.st_mode & 0o777),
                          device: UInt64(before.st_dev), inode: UInt64(before.st_ino))
    }

    enum ArtifactState: Equatable {
        case missing
        case present(FileRecord)
    }

    func observeArtifactSet(paths: [HelperRootReleaseSet.Artifact: String]) throws -> [HelperRootReleaseSet.Artifact: FileRecord] {
        guard Set(paths.keys) == Set(HelperRootReleaseSet.Artifact.allCases) else {
            throw ObservationError.invalidRelativePath
        }
        var records: [HelperRootReleaseSet.Artifact: FileRecord] = [:]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            guard let path = paths[artifact] else { throw ObservationError.invalidRelativePath }
            records[artifact] = try observeFile(relativePath: path)
        }
        return records
    }

    /// Missing leaf or parent paths are represented explicitly. Permission, symlink, ownership,
    /// type, and read errors are never downgraded to "missing".
    func observeArtifactSetAllowingMissing(paths: [HelperRootReleaseSet.Artifact: String]) throws -> [HelperRootReleaseSet.Artifact: ArtifactState] {
        guard Set(paths.keys) == Set(HelperRootReleaseSet.Artifact.allCases) else {
            throw ObservationError.invalidRelativePath
        }
        var result: [HelperRootReleaseSet.Artifact: ArtifactState] = [:]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            guard let path = paths[artifact] else { throw ObservationError.invalidRelativePath }
            do { result[artifact] = .present(try observeFile(relativePath: path)) }
            catch ObservationError.openFailed(let code) where code == ENOENT { result[artifact] = .missing }
        }
        return result
    }

    /// The pointer is only a hint. Callers must compare its release ID/generation and hashes with
    /// independently observed artifact bytes and the signed release before accepting it.
    func observeActiveReleasePointer() throws -> ReleasePointer {
        let record = try observeFile(relativePath: HelperRootReleaseSet.activeReleasePointerPath, privateFile: true)
        let data = try readSmallFileAgain(relativePath: record.relativePath, expectedHash: record.sha256)
        guard let pointer = try? JSONDecoder().decode(ReleasePointer.self, from: data), pointer.validate() else {
            throw ObservationError.decodePointerFailed
        }
        return pointer
    }

    private static func timestampsEqual(_ lhs: stat, _ rhs: stat) -> Bool {
        #if canImport(Darwin)
        return lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
        #elseif canImport(Glibc)
        return lhs.st_mtim.tv_sec == rhs.st_mtim.tv_sec
            && lhs.st_mtim.tv_nsec == rhs.st_mtim.tv_nsec
            && lhs.st_ctim.tv_sec == rhs.st_ctim.tv_sec
            && lhs.st_ctim.tv_nsec == rhs.st_ctim.tv_nsec
        #else
        return true
        #endif
    }

    private func readSmallFileAgain(relativePath: String, expectedHash: String) throws -> Data {
        // Re-open through the same descriptor-safe path. The hash equality detects replacement
        // between the metadata observation and decode; the acceptance lock closes the remaining race.
        let components = try validatedComponents(relativePath)
        let rootFD = try openVerifiedRoot(); defer { _ = close(rootFD) }
        var dirFD = rootFD; var owns = false
        defer { if owns { _ = close(dirFD) } }
        for component in components.dropLast() {
            let next = component.withCString { openat(dirFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { throw ObservationError.openFailed(errno) }
            var directoryInfo = stat()
            guard fstat(next, &directoryInfo) == 0,
                  (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  directoryInfo.st_uid == expectedOwnerUID,
                  (directoryInfo.st_mode & 0o022) == 0 else {
                _ = close(next); throw ObservationError.unsafeDirectory
            }
            if owns { _ = close(dirFD) }; dirFD = next; owns = true
        }
        let fd = components.last!.withCString { openat(dirFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        guard fd >= 0 else { throw ObservationError.openFailed(errno) }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == expectedOwnerUID, info.st_nlink == 1,
              (info.st_mode & 0o077) == 0, info.st_size >= 0, info.st_size <= maximumPointerBytes else {
            throw ObservationError.unsafeFile
        }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            #if canImport(Darwin)
            let count = Darwin.read(fd, &buffer, buffer.count)
            #elseif canImport(Glibc)
            let count = Glibc.read(fd, &buffer, buffer.count)
            #else
            let count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw ObservationError.readFailed(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maximumPointerBytes else { throw ObservationError.oversized }
        }
        guard SHA256Digest.hex(data) == expectedHash else { throw ObservationError.fileChangedDuringRead }
        return data
    }

    private func validatedComponents(_ relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !relativePath.contains("\0") else { throw ObservationError.invalidRelativePath }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil }) else {
            throw ObservationError.invalidRelativePath
        }
        return components
    }

    private func openVerifiedRoot() throws -> Int32 {
        guard jbRootPath.hasPrefix("/"), jbRootPath != "/", !jbRootPath.contains("\0") else {
            throw ObservationError.invalidRoot
        }
        let parts = jbRootPath.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else { throw ObservationError.invalidRoot }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ObservationError.rootUnavailable(errno) }
        for (index, part) in parts.enumerated() {
            let next = part.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw ObservationError.rootUnavailable(code) }
            var componentInfo = stat()
            let isFinal = index == parts.count - 1
            guard fstat(next, &componentInfo) == 0,
                  (componentInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  (!isFinal || componentInfo.st_uid == expectedOwnerUID),
                  (componentInfo.st_mode & 0o022) == 0,
                  (isFinal || componentInfo.st_uid == 0 || (componentInfo.st_mode & 0o200) == 0) else {
                _ = close(next); _ = close(fd); throw ObservationError.unsafeDirectory
            }
            _ = close(fd); fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == expectedOwnerUID, (info.st_mode & 0o022) == 0 else {
            _ = close(fd); throw ObservationError.unsafeDirectory
        }
        return fd
    }
}

/// Converts descriptor-verified file observations into the existing recovery assessment model.
/// Service/launchd facts remain supplied by a separate authenticated service observer.
struct HelperInstallerArtifactReconciliationBackend {
    struct Result: Equatable {
        let activeArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let stagedArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let previousArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let activeReleasePointer: HelperInstallerDescriptorFilesystemObserver.ReleasePointer?
        let activePointerMatchesObservedArtifacts: Bool
        let ownershipVerified: Bool
    }

    let observer: HelperInstallerDescriptorFilesystemObserver

    func observe(activePaths: [HelperRootReleaseSet.Artifact: String],
                 stagedPaths: [HelperRootReleaseSet.Artifact: String],
                 previousPaths: [HelperRootReleaseSet.Artifact: String]?) throws -> Result {
        let active = try observer.observeArtifactSetAllowingMissing(paths: activePaths)
        let staged = try observer.observeArtifactSetAllowingMissing(paths: stagedPaths)
        let previous = try previousPaths.map { try observer.observeArtifactSetAllowingMissing(paths: $0) } ?? [:]
        let pointer: HelperInstallerDescriptorFilesystemObserver.ReleasePointer?
        do { pointer = try observer.observeActiveReleasePointer() }
        catch HelperInstallerDescriptorFilesystemObserver.ObservationError.openFailed(let code) where code == ENOENT { pointer = nil }
        let allStates = Array(active.values) + Array(staged.values) + Array(previous.values)
        let presentRecords = allStates.compactMap { state -> HelperInstallerDescriptorFilesystemObserver.FileRecord? in
            if case .present(let record) = state { return record }; return nil
        }
        // Absence is a valid crash-recovery fact. Every file that does exist must be root-owned,
        // single-link, regular, and non-group/world-writable (enforced by the observer).
        let ownership = presentRecords.allSatisfy { $0.ownerUID == 0 && $0.inode > 0 }
        let activeHashes = active.reduce(into: [String: String]()) { output, item in
            if case .present(let record) = item.value { output[item.key.rawValue] = record.sha256 }
        }
        let pointerMatches = pointer.map { $0.artifactHashes == activeHashes
            && activeHashes.count == HelperRootReleaseSet.Artifact.allCases.count } ?? false
        return Result(activeArtifacts: active, stagedArtifacts: staged,
                      previousArtifacts: previous, activeReleasePointer: pointer,
                      activePointerMatchesObservedArtifacts: pointerMatches,
                      ownershipVerified: ownership)
    }

    func recoverySnapshot(from result: Result,
                          verifiedStagedRelease: HelperRootReleaseSet.Verified?,
                          previousReleaseExpectedHashes: [HelperRootReleaseSet.Artifact: String]?,
                          serviceRunning: Bool,
                          serviceIdentityMatchesRelease: Bool,
                          provisioningEnvelopeSHA256: String?,
                          previousProvisioningEnvelopeSHA256: String?) -> HelperInstallerRecoverySnapshot {
        func hashes(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]) -> [HelperRootReleaseSet.Artifact: String] {
            var output: [HelperRootReleaseSet.Artifact: String] = [:]
            for (artifact, state) in states {
                if case .present(let record) = state { output[artifact] = record.sha256 }
            }
            return output
        }
        let stagedHashes = hashes(result.stagedArtifacts)
        let stagedReleaseIdentifier = verifiedStagedRelease.flatMap {
            stagedHashes == $0.hashes ? $0.releaseIdentifier : nil
        }
        let previousHashes = hashes(result.previousArtifacts)
        let previousPreserved: Bool
        if let expected = previousReleaseExpectedHashes {
            previousPreserved = Set(expected.keys) == Set(HelperRootReleaseSet.Artifact.allCases)
                && previousHashes == expected
        } else { previousPreserved = false }
        let previousStatesComplete = previousReleaseExpectedHashes != nil
            && result.previousArtifacts.count == HelperRootReleaseSet.Artifact.allCases.count
            && result.previousArtifacts.values.allSatisfy { if case .present = $0 { return true }; return false }
        let pointer = result.activeReleasePointer
        return HelperInstallerRecoverySnapshot(
            stagedArtifactHashes: stagedHashes,
            artifactOwnershipVerified: result.ownershipVerified,
            previousReleasePreserved: previousPreserved,
            previousArtifactHashes: previousReleaseExpectedHashes == nil ? nil : previousHashes,
            previousArtifactOwnershipVerified: previousStatesComplete && result.ownershipVerified,
            stagedReleaseIdentifier: stagedReleaseIdentifier,
            activeReleaseIdentifier: result.activePointerMatchesObservedArtifacts ? pointer?.releaseIdentifier : nil,
            serviceRunning: serviceRunning,
            serviceIdentityMatchesRelease: serviceIdentityMatchesRelease,
            provisioningEnvelopeSHA256: provisioningEnvelopeSHA256,
            previousProvisioningEnvelopeSHA256: previousProvisioningEnvelopeSHA256)
    }

    func rootReleaseAssessment(state: HelperInstallerTransactionJournal.State,
                               newHashes: [HelperRootReleaseSet.Artifact: String],
                               previousHashes: [HelperRootReleaseSet.Artifact: String?],
                               result: Result) -> HelperRootReleaseRecoveryAssessment {
        func observation(_ state: HelperInstallerDescriptorFilesystemObserver.ArtifactState?) -> (String?, Bool) {
            guard let state else { return (nil, false) }
            if case .present(let record) = state { return (record.sha256, record.ownerUID == 0 && record.inode > 0) }
            return (nil, false)
        }
        let artifacts = HelperRootReleaseSet.Artifact.allCases.map { artifact -> HelperRootReleaseRecoveryAssessment.ArtifactObservation in
            let current = observation(result.activeArtifacts[artifact])
            let backup = observation(result.previousArtifacts[artifact])
            return .init(currentHash: current.0, previousBackupHash: backup.0,
                         currentOwnedByFilterKit: current.1, backupOwnedByFilterKit: backup.1)
        }
        let snapshot = HelperRootReleaseRecoveryAssessment.Snapshot(
            executable: artifacts[0], manifest: artifacts[1], launchDaemon: artifacts[2])
        return HelperRootReleaseRecoveryAssessment.assess(state: state, newHashes: newHashes,
                                                          previousHashes: previousHashes, snapshot: snapshot)
    }
}
