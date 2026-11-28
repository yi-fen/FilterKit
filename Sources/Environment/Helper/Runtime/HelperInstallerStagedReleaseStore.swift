import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Root-owned quarantine for verified Helper release artifacts. This is deliberately distinct
/// from provisioning.stagingRootPath, which is the App-owned plugin-payload staging directory.
/// The directory must be provisioned before use; this store never creates/chowns/chmods it.
struct HelperInstallerStagedReleaseStore {
    enum StoreError: Error, Equatable {
        case notRoot, invalidRoot, openFailed(Int32), unsafeDirectory, unsafeArtifact
        case invalidPreparedRelease, artifactVerificationFailed, machOIdentityMismatch
        case journalIntentRequired, journalCommitIndeterminate
        case transactionAlreadyExists, missingTransaction, partialTransaction
        case writeFailed(Int32), syncFailed(Int32), renameFailed(Int32)
        case injectedCrash(HelperRootReleaseSet.Artifact)
    }

    enum State: Equatable { case missing, complete, partial, mismatched }
    enum FaultPoint: Equatable { case afterExecutable, afterManifest, afterLaunchDaemon }

    struct Receipt: Equatable {
        let transactionID: UUID
        let releaseIdentifier: String
        let generation: UInt64
        let relativeDirectory: String
        let hashes: [HelperRootReleaseSet.Artifact: String]
        let byteCounts: [HelperRootReleaseSet.Artifact: Int]
    }

    struct Inspection: Equatable {
        let state: State
        let transactionID: UUID
        let observedHashes: [HelperRootReleaseSet.Artifact: String]
        let missingArtifacts: Set<HelperRootReleaseSet.Artifact>
        let mismatchedArtifacts: Set<HelperRootReleaseSet.Artifact>
        let unexpectedEntries: Set<String>
    }

    /// Fixed root-owned location under JBROOT. It is not the App-owned plugin payload staging root.
    static let relativeRootPath = "Library/FilterKit/Helper/StagedReleases"
    private let jbRootPath: String

    init(jbRootPath: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(jbRootPath), jbRootPath != "/" else {
            throw StoreError.invalidRoot
        }
        self.jbRootPath = jbRootPath
    }

    /// Stages only a HelperPreparedRootInstall created by HelperTrustedInstallerCoordinator.prepare.
    /// The signed envelope is re-bound to the prepared digest and all three artifact hashes are
    /// reverified before any filesystem write. This method does not activate or launch Helper.
    func stage(prepared: HelperPreparedRootInstall,
               journal: HelperInstallerTransactionJournal,
               journalStore: HelperInstallerDurableJournalStore,
               artifacts: [String: Data],
               faultAt: FaultPoint? = nil) throws -> Receipt {
        #if canImport(Darwin)
        return try HelperInstallerSharedTransactionLock.withExclusiveLock(jbroot: jbRootPath) {
            try stageLocked(prepared: prepared, journal: journal, journalStore: journalStore,
                            artifacts: artifacts, faultAt: faultAt)
        }
        #else
        // Linux Host smoke exercises the descriptor-relative writer without pretending to test
        // Darwin flock behavior. Production Darwin builds always take the shared installer lock.
        return try stageLocked(prepared: prepared, journal: journal, journalStore: journalStore,
                               artifacts: artifacts, faultAt: faultAt)
        #endif
    }

    private func stageLocked(prepared: HelperPreparedRootInstall,
               journal: HelperInstallerTransactionJournal,
               journalStore: HelperInstallerDurableJournalStore,
               artifacts: [String: Data],
               faultAt: FaultPoint?) throws -> Receipt {
        guard geteuid() == 0 else { throw StoreError.notRoot }
        guard prepared.plan.jbRootPath == jbRootPath,
              SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256,
              let envelope = try? JSONDecoder().decode(HelperSignedProvisioningManifest.self,
                                                       from: prepared.provisioningEnvelopeData),
              envelope.payload.jbRootPath == jbRootPath,
              envelope.payload.releaseIdentifier == prepared.release.releaseIdentifier,
              envelope.payload.generation == prepared.release.generation else {
            throw StoreError.invalidPreparedRelease
        }
        let digestPaths: [HelperRootReleaseSet.Artifact: String] = [
            .executable: HelperRootReleaseSet.executablePath,
            .deploymentManifest: HelperRootReleaseSet.manifestPath,
            .launchDaemon: HelperRootReleaseSet.launchDaemonPath
        ]
        let expected = digestPaths.map { artifact, path in
            HelperInstallerArtifactDigest(relativePath: path, sha256: prepared.release.hashes[artifact] ?? "")
        }
        let verified: HelperRootReleaseSet.Verified
        do {
            verified = try HelperRootReleaseSet().verify(bundle: envelope.payload,
                artifacts: artifacts, expectedDigests: expected)
        } catch { throw StoreError.artifactVerificationFailed }
        guard verified == prepared.release,
              let executable = artifacts[HelperRootReleaseSet.executablePath] else {
            throw StoreError.artifactVerificationFailed
        }
        try verifyMachOIdentity(executable, expectedCDHash: envelope.payload.helperCDHash,
                                expectedTeamIdentifier: envelope.payload.teamIdentifier)

        let baseFD = try openVerifiedStagingRoot()
        defer { _ = close(baseFD) }
        let transactionName = prepared.initialJournal.transactionID.uuidString.lowercased()
        var existing = stat()
        let existingResult = transactionName.withCString {
            fstatat(baseFD, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if existingResult == 0 { throw StoreError.transactionAlreadyExists }
        guard errno == ENOENT else { throw StoreError.openFailed(errno) }
        let persistedJournal: HelperInstallerTransactionJournal
        do { persistedJournal = try journalStore.load(transactionID: journal.transactionID) }
        catch { throw StoreError.journalIntentRequired }
        let validJournalState = (journal.action == .install && journal.state == .artifactsVerified) ||
            ((journal.action == .upgrade || journal.action == .repin) && journal.state == .previousReleasePreserved)
        guard journal.transactionID == prepared.initialJournal.transactionID,
              journal.action == prepared.plan.action,
              journal.releaseIdentifier == prepared.release.releaseIdentifier,
              journal.generation == prepared.release.generation,
              journal.pendingOperation == .stageRelease,
              validJournalState, persistedJournal == journal else {
            throw StoreError.journalIntentRequired
        }
        let createResult = transactionName.withCString { mkdirat(baseFD, $0, 0o700) }
        guard createResult == 0 else {
            if errno == EEXIST { throw StoreError.transactionAlreadyExists }
            throw StoreError.openFailed(errno)
        }
        guard fsync(baseFD) == 0 else {
            let code = errno
            _ = transactionName.withCString { unlinkat(baseFD, $0, AT_REMOVEDIR) }
            throw StoreError.syncFailed(code)
        }
        let transactionFD = transactionName.withCString {
            openat(baseFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard transactionFD >= 0 else {
            let code = errno
            _ = transactionName.withCString { unlinkat(baseFD, $0, AT_REMOVEDIR) }
            throw StoreError.openFailed(code)
        }
        defer { _ = close(transactionFD) }
        do {
            try validatePrivateDirectory(transactionFD)
            for artifact in HelperRootReleaseSet.Artifact.allCases {
                guard let path = digestPaths[artifact], let bytes = artifacts[path],
                      let expectedHash = verified.hashes[artifact],
                      SHA256Digest.hex(bytes) == expectedHash else {
                    throw StoreError.artifactVerificationFailed
                }
                try writeArtifact(bytes, artifact: artifact, expectedHash: expectedHash,
                                  directoryFD: transactionFD)
                guard try hashArtifact(fileName(for: artifact), artifact: artifact,
                                       directoryFD: transactionFD) == expectedHash else {
                    throw StoreError.unsafeArtifact
                }
                if (artifact == .executable && faultAt == .afterExecutable) ||
                   (artifact == .deploymentManifest && faultAt == .afterManifest) ||
                   (artifact == .launchDaemon && faultAt == .afterLaunchDaemon) {
                    throw StoreError.injectedCrash(artifact)
                }
            }
            guard try entryNames(directoryFD: transactionFD) == expectedEntryNames,
                  fsync(transactionFD) == 0, fsync(baseFD) == 0 else { throw StoreError.unsafeArtifact }
        } catch let StoreError.injectedCrash(artifact) {
            // Preserve the partial directory exactly as a process crash would. Inspection is
            // read-only and will classify it as partial; no automatic promotion is permitted.
            throw StoreError.injectedCrash(artifact)
        } catch {
            // Only remove the transaction directory created by this call. Never touch a
            // pre-existing directory or files outside this descriptor-relative namespace.
            removeKnownArtifacts(directoryFD: transactionFD)
            _ = transactionName.withCString { unlinkat(baseFD, $0, AT_REMOVEDIR) }
            _ = fsync(baseFD)
            throw error
        }

        var completedJournal = journal
        do {
            try completedJournal.apply(.stageRelease)
            try journalStore.save(completedJournal)
        } catch {
            // The staged bytes are durable but the Journal completion is not proven. Preserve
            // them for read-only recovery reconciliation; never delete or activate on ambiguity.
            throw StoreError.journalCommitIndeterminate
        }
        return Receipt(transactionID: prepared.initialJournal.transactionID,
            releaseIdentifier: verified.releaseIdentifier, generation: verified.generation,
            relativeDirectory: Self.relativeRootPath + "/" + transactionName,
            hashes: verified.hashes, byteCounts: verified.byteCounts)
    }

    /// Reads the complete staged artifact set through verified directory/file descriptors.
    /// Intended for callers that already hold the activation transaction lock; this method does
    /// not acquire another lock and therefore cannot create a nested-lock deadlock.
    func loadVerifiedArtifactsForActivation(transactionID: UUID,
                                            expectedHashes: [HelperRootReleaseSet.Artifact: String]) throws -> [HelperRootReleaseSet.Artifact: Data] {
        guard Set(expectedHashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              expectedHashes.values.allSatisfy(HelperPolicy.isValidHash) else { throw StoreError.artifactVerificationFailed }
        let baseFD = try openVerifiedStagingRoot(); defer { _ = close(baseFD) }
        let name = transactionID.uuidString.lowercased()
        let directoryFD = name.withCString { openat(baseFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard directoryFD >= 0 else { throw StoreError.missingTransaction }
        defer { _ = close(directoryFD) }
        try validatePrivateDirectory(directoryFD)
        guard try entryNames(directoryFD: directoryFD) == expectedEntryNames else { throw StoreError.unsafeArtifact }
        var result: [HelperRootReleaseSet.Artifact: Data] = [:]
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            let bytes = try readArtifact(fileName(for: artifact), artifact: artifact, directoryFD: directoryFD)
            guard let expected = expectedHashes[artifact], SHA256Digest.hex(bytes) == expected else {
                throw StoreError.artifactVerificationFailed
            }
            result[artifact] = bytes
        }
        return result
    }

    /// Read-only inspection. A partial or mismatched set is never repaired or promoted here.
    func inspect(prepared: HelperPreparedRootInstall) throws -> Inspection {
        #if canImport(Darwin)
        return try HelperInstallerSharedTransactionLock.withExclusiveLock(jbroot: jbRootPath) {
            try inspectLocked(prepared: prepared)
        }
        #else
        return try inspectLocked(prepared: prepared)
        #endif
    }

    private func inspectLocked(prepared: HelperPreparedRootInstall) throws -> Inspection {
        guard prepared.plan.jbRootPath == jbRootPath else { throw StoreError.invalidPreparedRelease }
        let baseFD = try openVerifiedStagingRoot()
        defer { _ = close(baseFD) }
        let name = prepared.initialJournal.transactionID.uuidString.lowercased()
        let directoryFD = name.withCString {
            openat(baseFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        if directoryFD < 0 {
            if errno == ENOENT {
                return Inspection(state: .missing, transactionID: prepared.initialJournal.transactionID,
                                  observedHashes: [:], missingArtifacts: Set(HelperRootReleaseSet.Artifact.allCases),
                                  mismatchedArtifacts: [], unexpectedEntries: [])
            }
            throw StoreError.openFailed(errno)
        }
        defer { _ = close(directoryFD) }
        try validatePrivateDirectory(directoryFD)
        let observedEntries = try entryNames(directoryFD: directoryFD)
        let unexpectedEntries = observedEntries.subtracting(expectedEntryNames)
        var hashes: [HelperRootReleaseSet.Artifact: String] = [:]
        var missing = Set<HelperRootReleaseSet.Artifact>()
        var mismatched = Set<HelperRootReleaseSet.Artifact>()
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            let name = fileName(for: artifact)
            do {
                let observed = try hashArtifact(name, artifact: artifact, directoryFD: directoryFD)
                hashes[artifact] = observed
                if observed != prepared.release.hashes[artifact] { mismatched.insert(artifact) }
            } catch StoreError.missingTransaction {
                missing.insert(artifact)
            }
        }
        let state: State = (!mismatched.isEmpty || !unexpectedEntries.isEmpty) ? .mismatched : (!missing.isEmpty ? .partial : .complete)
        return Inspection(state: state, transactionID: prepared.initialJournal.transactionID,
                          observedHashes: hashes, missingArtifacts: missing, mismatchedArtifacts: mismatched,
                          unexpectedEntries: unexpectedEntries)
    }

    private var expectedEntryNames: Set<String> {
        Set(HelperRootReleaseSet.Artifact.allCases.map { fileName(for: $0) })
    }

    private func entryNames(directoryFD: Int32) throws -> Set<String> {
        let duplicate = dup(directoryFD)
        guard duplicate >= 0 else { throw StoreError.openFailed(errno) }
        guard let stream = fdopendir(duplicate) else {
            let code = errno; _ = close(duplicate); throw StoreError.openFailed(code)
        }
        defer { _ = closedir(stream) }
        var result = Set<String>()
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { result.insert(name) }
        }
        return result
    }

    private func openVerifiedStagingRoot() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        let components = (jbRootPath + "/" + Self.relativeRootPath).split(separator: "/").map(String.init)
        guard !components.isEmpty else { _ = close(fd); throw StoreError.invalidRoot }
        for (index, component) in components.enumerated() {
            let next = component.withCString {
                openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else { let code = errno; _ = close(fd); throw StoreError.openFailed(code) }
            _ = close(fd); fd = next
            var info = stat()
            guard fstat(fd, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  (info.st_mode & 0o022) == 0,
                  info.st_uid == 0 || (info.st_mode & 0o200) == 0 else {
                _ = close(fd); throw StoreError.unsafeDirectory
            }
            if index == components.count - 1 {
                guard info.st_uid == 0, info.st_gid == 0,
                      (info.st_mode & 0o777) == 0o700 else {
                    _ = close(fd); throw StoreError.unsafeDirectory
                }
            }
        }
        return fd
    }

    private func validatePrivateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o700 else { throw StoreError.unsafeDirectory }
    }

    private func writeArtifact(_ data: Data, artifact: HelperRootReleaseSet.Artifact,
                               expectedHash: String, directoryFD: Int32) throws {
        let finalName = fileName(for: artifact)
        let temporaryName = "." + finalName + "." + UUID().uuidString.lowercased() + ".tmp"
        let mode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let fd = temporaryName.withCString {
            openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        }
        guard fd >= 0 else { throw StoreError.openFailed(errno) }
        var keepTemporary = true
        defer {
            _ = close(fd)
            if keepTemporary { _ = temporaryName.withCString { unlinkat(directoryFD, $0, 0) } }
        }
        guard fchmod(fd, mode) == 0 else { throw StoreError.writeFailed(errno) }
        try writeAll(data, to: fd)
        guard fsync(fd) == 0 else { throw StoreError.syncFailed(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_uid == 0, info.st_gid == 0, info.st_nlink == 1,
              (info.st_mode & 0o777) == mode, (info.st_mode & 0o6000) == 0,
              SHA256Digest.hex(data) == expectedHash else { throw StoreError.unsafeArtifact }
        let renameResult = temporaryName.withCString { source in
            finalName.withCString { destination in renameat(directoryFD, source, directoryFD, destination) }
        }
        guard renameResult == 0 else { throw StoreError.renameFailed(errno) }
        keepTemporary = false
        guard fsync(directoryFD) == 0 else { throw StoreError.syncFailed(errno) }
    }

    private func readArtifact(_ name: String, artifact: HelperRootReleaseSet.Artifact,
                              directoryFD: Int32) throws -> Data {
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        if fd < 0 { if errno == ENOENT { throw StoreError.missingTransaction }; throw StoreError.openFailed(errno) }
        defer { _ = close(fd) }
        let expectedMode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let maximumSize: Int64 = artifact == .executable ? 64 * 1024 * 1024 : 256 * 1024
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_uid == 0, before.st_gid == 0, before.st_nlink == 1,
              (before.st_mode & 0o777) == expectedMode, (before.st_mode & 0o6000) == 0,
              before.st_size >= 0, before.st_size <= maximumSize else { throw StoreError.unsafeArtifact }
        var bytes = Data(); bytes.reserveCapacity(Int(before.st_size)); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int
            #if canImport(Darwin)
            count = Darwin.read(fd, &buffer, buffer.count)
            #elseif canImport(Glibc)
            count = Glibc.read(fd, &buffer, buffer.count)
            #else
            count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.openFailed(errno) }
            if count == 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
            guard bytes.count <= Int(maximumSize) else { throw StoreError.unsafeArtifact }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, FileIdentity(before) == FileIdentity(after),
              bytes.count == Int(after.st_size) else { throw StoreError.unsafeArtifact }
        return bytes
    }

    private func hashArtifact(_ name: String, artifact: HelperRootReleaseSet.Artifact,
                              directoryFD: Int32) throws -> String {
        let fd = name.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        if fd < 0 {
            if errno == ENOENT { throw StoreError.missingTransaction }
            throw StoreError.openFailed(errno)
        }
        defer { _ = close(fd) }
        var before = stat()
        let expectedMode: mode_t = artifact == .executable ? 0o755 : (artifact == .deploymentManifest ? 0o600 : 0o644)
        let maximumSize: Int64 = artifact == .executable ? 64 * 1024 * 1024 : 256 * 1024
        guard fstat(fd, &before) == 0,
              (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              before.st_uid == 0, before.st_gid == 0, before.st_nlink == 1,
              (before.st_mode & 0o777) == expectedMode, (before.st_mode & 0o6000) == 0,
              before.st_size >= 0, before.st_size <= maximumSize else { throw StoreError.unsafeArtifact }
        var bytes = Data(); bytes.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int
            #if canImport(Darwin)
            count = Darwin.read(fd, &buffer, buffer.count)
            #elseif canImport(Glibc)
            count = Glibc.read(fd, &buffer, buffer.count)
            #else
            count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw StoreError.openFailed(errno) }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
            guard bytes.count <= Int(maximumSize) else { throw StoreError.unsafeArtifact }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, FileIdentity(before) == FileIdentity(after),
              bytes.count == Int(after.st_size) else { throw StoreError.unsafeArtifact }
        return SHA256Digest.hex(bytes)
    }

    private func verifyMachOIdentity(_ executable: Data, expectedCDHash: String,
                                     expectedTeamIdentifier: String?) throws {
        let slices: [MachOSliceMetadata]
        do { slices = try MachOMetadataReader().readSlices(data: executable) }
        catch { throw StoreError.machOIdentityMismatch }
        guard !slices.isEmpty,
              slices.allSatisfy({ $0.codeSignatureState == "cdhash_extracted" &&
                  $0.codeSignatureTeamIdentifier == expectedTeamIdentifier }),
              slices.contains(where: { $0.cdHash?.caseInsensitiveCompare(expectedCDHash) == .orderedSame }) else {
            throw StoreError.machOIdentityMismatch
        }
    }

    private func fileName(for artifact: HelperRootReleaseSet.Artifact) -> String {
        switch artifact {
        case .executable: return "filterkit-helper"
        case .deploymentManifest: return "Deployment.json"
        case .launchDaemon: return "cn.yfen.filterkit.helper.plist"
        }
    }

    private func removeKnownArtifacts(directoryFD: Int32) {
        for artifact in HelperRootReleaseSet.Artifact.allCases {
            let name = fileName(for: artifact)
            _ = name.withCString { unlinkat(directoryFD, $0, 0) }
            let prefix = "." + name + "."
            // Temporary files are unique and private. Enumerating a directory here would require
            // a separate stream API; failed temporary files are removed by writeArtifact's defer.
            _ = prefix
        }
        _ = fsync(directoryFD)
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count: Int
                #if canImport(Darwin)
                count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                #elseif canImport(Glibc)
                count = Glibc.write(fd, base.advanced(by: offset), raw.count - offset)
                #else
                count = -1
                #endif
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StoreError.writeFailed(count == 0 ? EIO : errno) }
                offset += count
            }
        }
    }

    private struct FileIdentity: Equatable {
        let device: UInt64; let inode: UInt64; let size: Int64
        let modifiedSeconds: Int64; let modifiedNanos: Int64
        let changedSeconds: Int64; let changedNanos: Int64
        init(_ value: stat) {
            device = UInt64(value.st_dev); inode = UInt64(value.st_ino); size = Int64(value.st_size)
            #if canImport(Darwin)
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec); modifiedNanos = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec); changedNanos = Int64(value.st_ctimespec.tv_nsec)
            #elseif canImport(Glibc)
            modifiedSeconds = Int64(value.st_mtim.tv_sec); modifiedNanos = Int64(value.st_mtim.tv_nsec)
            changedSeconds = Int64(value.st_ctim.tv_sec); changedNanos = Int64(value.st_ctim.tv_nsec)
            #else
            modifiedSeconds = 0; modifiedNanos = 0; changedSeconds = 0; changedNanos = 0
            #endif
        }
    }
}
