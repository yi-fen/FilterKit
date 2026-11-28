import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A baseline can only be created by the trusted store after signature and monotonic-checkpoint
/// validation. Callers cannot manufacture one from a decoded payload or signature alone.
struct HelperVerifiedProvisioningBaseline: Equatable {
    let payload: HelperInstallerProvisioningBundle
    let envelopeSHA256: String
    fileprivate init(payload: HelperInstallerProvisioningBundle, envelopeSHA256: String) {
        self.payload = payload
        self.envelopeSHA256 = envelopeSHA256
    }
}

private extension JSONEncoder {
    static var sortedProvisioning: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Narrow persistence contract. Implementations must provide atomic same-directory replacement.
protocol HelperProvisioningAtomicPersistence {
    func read(_ leaf: String) throws -> Data?
    func writeAtomically(_ data: Data, to leaf: String) throws
    func remove(_ leaf: String) throws
}

/// Root-owned persistence under an installer-created 0700 directory. It never creates the
/// directory or changes ownership/mode. Only the two fixed leaf names are accepted.
struct HelperRootOwnedProvisioningFileStore: HelperProvisioningAtomicPersistence {
    enum Failure: Error, Equatable { case invalidDirectory, unsafeDirectory, unsafeFile, io(Int32), oversized }
    private let directoryPath: String
    private let maximumBytes: Int
    private let allowedLeaves: Set<String> = ["provisioning.signed.json", "provisioning.pending.json"]

    init(directoryPath: String, maximumBytes: Int = 128 * 1024) {
        self.directoryPath = directoryPath
        self.maximumBytes = max(4096, maximumBytes)
    }

    func read(_ leaf: String) throws -> Data? {
        let dir = try openDirectory(); defer { _ = close(dir) }
        guard allowedLeaves.contains(leaf) else { throw Failure.invalidDirectory }
        let fd = leaf.withCString { openat(dir, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 { if errno == ENOENT { return nil }; throw Failure.io(errno) }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_uid == 0,
              info.st_gid == 0, (info.st_mode & 0o777) == 0o600 else { throw Failure.unsafeFile }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw Failure.oversized }
        var data = Data(); data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            #if canImport(Darwin)
            let count = Darwin.read(fd, &buffer, buffer.count)
            #elseif canImport(Glibc)
            let count = Glibc.read(fd, &buffer, buffer.count)
            #else
            let count = -1
            #endif
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure.io(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maximumBytes else { throw Failure.oversized }
        }
        return data
    }

    func writeAtomically(_ data: Data, to leaf: String) throws {
        guard allowedLeaves.contains(leaf), data.count <= maximumBytes else { throw Failure.oversized }
        let dir = try openDirectory(); defer { _ = close(dir) }
        let temp = "." + leaf + "." + UUID().uuidString.lowercased() + ".tmp"
        let fd = temp.withCString { openat(dir, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard fd >= 0 else { throw Failure.io(errno) }
        var keep = true
        defer { _ = close(fd); if keep { _ = temp.withCString { unlinkat(dir, $0, 0) } } }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                #if canImport(Darwin)
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                #elseif canImport(Glibc)
                let count = Glibc.write(fd, base.advanced(by: offset), raw.count - offset)
                #else
                let count = -1
                #endif
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io(errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw Failure.io(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_gid == 0,
              (info.st_mode & 0o777) == 0o600 else { throw Failure.unsafeFile }
        let rc = temp.withCString { src in leaf.withCString { dst in renameat(dir, src, dir, dst) } }
        guard rc == 0 else { throw Failure.io(errno) }
        keep = false
        guard fsync(dir) == 0 else { throw Failure.io(errno) }
    }

    func remove(_ leaf: String) throws {
        guard allowedLeaves.contains(leaf) else { throw Failure.invalidDirectory }
        let dir = try openDirectory(); defer { _ = close(dir) }
        let rc = leaf.withCString { unlinkat(dir, $0, 0) }
        if rc != 0 && errno != ENOENT { throw Failure.io(errno) }
        guard fsync(dir) == 0 else { throw Failure.io(errno) }
    }

    private func openDirectory() throws -> Int32 {
        guard directoryPath.hasPrefix("/"), !directoryPath.contains("\0"),
              directoryPath.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else { throw Failure.invalidDirectory }
        let components = directoryPath.split(separator: "/").map(String.init)
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io(errno) }
        for component in components {
            let next = component.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard next >= 0 else { let code = errno; _ = close(fd); throw Failure.io(code) }
            var componentInfo = stat()
            let metadataOK = fstat(next, &componentInfo) == 0 &&
                (componentInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) &&
                componentInfo.st_uid == 0 && componentInfo.st_gid == 0
            let writableParentSafe = (componentInfo.st_mode & 0o022) == 0 ||
                (componentInfo.st_mode & mode_t(S_ISVTX)) != 0
            guard metadataOK && writableParentSafe else {
                _ = close(next); _ = close(fd); throw Failure.unsafeDirectory
            }
            _ = close(fd); fd = next
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == 0, info.st_gid == 0, (info.st_mode & 0o777) == 0o700 else {
            _ = close(fd); throw Failure.unsafeDirectory
        }
        return fd
    }
}


struct HelperProvisioningCheckpoint: Equatable {
    let generation: UInt64
    let envelopeSHA256: String
}

protocol HelperProvisioningCheckpointStoring {
    func highestCheckpoint(for bundleIdentifier: String) throws -> HelperProvisioningCheckpoint?
    func record(_ checkpoint: HelperProvisioningCheckpoint, for bundleIdentifier: String) throws
}

/// Test-only process-local checkpoint implementation.
final class InMemoryHelperProvisioningCheckpointStore: HelperProvisioningCheckpointStoring {
    private var values: [String: HelperProvisioningCheckpoint] = [:]
    func highestCheckpoint(for bundleIdentifier: String) throws -> HelperProvisioningCheckpoint? { values[bundleIdentifier.lowercased()] }
    func record(_ checkpoint: HelperProvisioningCheckpoint, for bundleIdentifier: String) throws {
        let key = bundleIdentifier.lowercased()
        if let old = values[key] {
            guard checkpoint.generation > old.generation ||
                    (checkpoint.generation == old.generation && checkpoint.envelopeSHA256 == old.envelopeSHA256) else {
                throw HelperTrustedProvisioningStore.Failure.generationNotIncreasing
            }
        }
        values[key] = checkpoint
    }
}

#if canImport(Security)
import Security
/// Append-only, device-local Keychain checkpoint. A generation is immutable: a second digest
/// for the same generation is treated as corruption rather than replacing the first record.
final class KeychainHelperProvisioningCheckpointStore: HelperProvisioningCheckpointStoring {
    enum StoreFailure: Error { case invalidBundleIdentifier, keychain(OSStatus), malformedValue, generationConflict }
    private let service: String
    init(service: String = "cn.yfen.filterkit.provisioning-checkpoint") { self.service = service }

    func highestCheckpoint(for bundleIdentifier: String) throws -> HelperProvisioningCheckpoint? {
        guard Self.valid(bundleIdentifier) else { throw StoreFailure.invalidBundleIdentifier }
        let canonicalBundleIdentifier = bundleIdentifier.lowercased()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnAttributes as String: true,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else { throw StoreFailure.keychain(status) }
        let prefix = canonicalBundleIdentifier + "|generation|"
        var digestsByGeneration: [UInt64: String] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String, account.hasPrefix(prefix) else { continue }
            let suffix = account.dropFirst(prefix.count)
            guard let generation = UInt64(suffix), generation > 0,
                  let data = row[kSecValueData as String] as? Data,
                  let digest = String(data: data, encoding: .utf8), HelperPolicy.isValidHash(digest) else {
                throw StoreFailure.malformedValue
            }
            if let oldDigest = digestsByGeneration[generation], oldDigest != digest {
                throw StoreFailure.generationConflict
            }
            digestsByGeneration[generation] = digest
        }
        guard let generation = digestsByGeneration.keys.max(),
              let digest = digestsByGeneration[generation] else { return nil }
        return HelperProvisioningCheckpoint(generation: generation, envelopeSHA256: digest)
    }

    func record(_ checkpoint: HelperProvisioningCheckpoint, for bundleIdentifier: String) throws {
        guard Self.valid(bundleIdentifier), checkpoint.generation > 0,
              HelperPolicy.isValidHash(checkpoint.envelopeSHA256) else { throw StoreFailure.invalidBundleIdentifier }
        let canonicalBundleIdentifier = bundleIdentifier.lowercased()
        if let old = try highestCheckpoint(for: canonicalBundleIdentifier) {
            if checkpoint.generation == old.generation && checkpoint.envelopeSHA256 == old.envelopeSHA256 { return }
            guard checkpoint.generation > old.generation else { throw StoreFailure.generationConflict }
        }
        let account = canonicalBundleIdentifier + "|generation|" + String(format: "%020llu", checkpoint.generation)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        var insert = query
        insert[kSecValueData as String] = Data(checkpoint.envelopeSHA256.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreFailure.keychain(status) }
    }

    private static func valid(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9.-]{3,255}$", options: .regularExpression) != nil
    }
}
#endif

/// A pending record is only a crash-recovery marker. Both envelope bytes are independently
/// authenticated before recovery decisions; the marker itself is never treated as provenance.
private struct HelperProvisioningPendingRecord: Codable {
    let transactionID: UUID
    let bundleIdentifier: String
    let generation: UInt64
    let previousDigest: String?
    let nextDigest: String
}

final class HelperTrustedProvisioningStore {
    enum Failure: Error, Equatable {
        case noTrustedBaseline, malformedPending, manualIntervention, signatureInvalid
        case rollbackDetected, generationNotIncreasing, identityRotationRejected
    }
    private let persistence: HelperProvisioningAtomicPersistence
    private let verifier: HelperProvisioningSignatureVerifier
    private let checkpointStore: HelperProvisioningCheckpointStoring
    private let lock = NSRecursiveLock()

    init(persistence: HelperProvisioningAtomicPersistence,
         verifier: HelperProvisioningSignatureVerifier,
         checkpointStore: HelperProvisioningCheckpointStoring) {
        self.persistence = persistence; self.verifier = verifier; self.checkpointStore = checkpointStore
    }

    func loadTrustedBaseline() throws -> HelperVerifiedProvisioningBaseline {
        lock.lock(); defer { lock.unlock() }
        try recoverPendingTransaction()
        guard let data = try persistence.read("provisioning.signed.json") else { throw Failure.noTrustedBaseline }
        let envelope = try decodeAndVerify(data)
        let payload = envelope.payload
        let checkpoint = HelperProvisioningCheckpoint(generation: payload.generation, envelopeSHA256: SHA256Digest.hex(data))
        if let highest = try checkpointStore.highestCheckpoint(for: payload.bundleIdentifier.lowercased()) {
            guard payload.generation >= highest.generation else { throw Failure.rollbackDetected }
            if payload.generation == highest.generation && checkpoint.envelopeSHA256 != highest.envelopeSHA256 {
                throw Failure.rollbackDetected
            }
            if payload.generation > highest.generation { try checkpointStore.record(checkpoint, for: payload.bundleIdentifier.lowercased()) }
        } else {
            try checkpointStore.record(checkpoint, for: payload.bundleIdentifier.lowercased())
        }
        return HelperVerifiedProvisioningBaseline(payload: payload, envelopeSHA256: checkpoint.envelopeSHA256)
    }

    /// Commits a signed candidate with a durable intent marker, atomic file replacement and
    /// append-only generation checkpoint. If interrupted, recovery reconciles current bytes
    /// against the signed pending digests before accepting or discarding the intent.
    func commit(_ candidateData: Data, action: HelperInstallerTransactionPlan.Action) throws -> HelperVerifiedProvisioningBaseline {
        lock.lock(); defer { lock.unlock() }
        try recoverPendingTransaction()
        let candidate = try decodeAndVerify(candidateData)
        let next = candidate.payload
        let oldData = try persistence.read("provisioning.signed.json")
        let oldBaseline: HelperVerifiedProvisioningBaseline?
        if oldData != nil {
            // Never use a merely well-formed signed file as a Repin baseline. It must also
            // match the device-local monotonic checkpoint before it can authorize rotation.
            oldBaseline = try loadTrustedBaseline()
            if oldData == candidateData, let oldBaseline { return oldBaseline }
        } else {
            oldBaseline = nil
        }
        if action == .install {
            guard oldData == nil else { throw Failure.generationNotIncreasing }
        } else if action == .repin {
            guard let old = oldBaseline?.payload else { throw Failure.noTrustedBaseline }
            do { try HelperClientCodeIdentityRotationPolicy.validate(previous: old, next: next) }
            catch { throw Failure.identityRotationRejected }
        } else if action == .upgrade {
            guard let old = oldBaseline?.payload,
                  next.generation == old.generation + 1,
                  old.bundleIdentifier.caseInsensitiveCompare(next.bundleIdentifier) == .orderedSame,
                  old.teamIdentifier == next.teamIdentifier,
                  old.appCDHash.caseInsensitiveCompare(next.appCDHash) == .orderedSame,
                  old.allowedClientUID == next.allowedClientUID,
                  old.socketGroupID == next.socketGroupID,
                  old.jbRootPath == next.jbRootPath,
                  old.routeIdentifier == next.routeIdentifier,
                  old.tweakInjectPath == next.tweakInjectPath,
                  old.stagingRootPath == next.stagingRootPath,
                  old.socketPath == next.socketPath else { throw Failure.identityRotationRejected }
        } else {
            throw Failure.generationNotIncreasing
        }
        let candidateCheckpoint = HelperProvisioningCheckpoint(generation: next.generation,
            envelopeSHA256: SHA256Digest.hex(candidateData))
        if let highest = try checkpointStore.highestCheckpoint(for: next.bundleIdentifier.lowercased()) {
            guard candidateCheckpoint.generation > highest.generation else { throw Failure.generationNotIncreasing }
        }
        let pending = HelperProvisioningPendingRecord(transactionID: UUID(), bundleIdentifier: next.bundleIdentifier,
            generation: next.generation, previousDigest: oldData.map(SHA256Digest.hex), nextDigest: SHA256Digest.hex(candidateData))
        let marker = try JSONEncoder.sortedProvisioning.encode(pending)
        try persistence.writeAtomically(marker, to: "provisioning.pending.json")
        try persistence.writeAtomically(candidateData, to: "provisioning.signed.json")
        try checkpointStore.record(candidateCheckpoint, for: next.bundleIdentifier.lowercased())
        try persistence.remove("provisioning.pending.json")
        return HelperVerifiedProvisioningBaseline(payload: next, envelopeSHA256: candidateCheckpoint.envelopeSHA256)
    }

    func recoverPendingTransaction() throws {
        lock.lock(); defer { lock.unlock() }
        guard let markerData = try persistence.read("provisioning.pending.json") else { return }
        guard let pending = try? JSONDecoder().decode(HelperProvisioningPendingRecord.self, from: markerData),
              pending.generation > 0, HelperPolicy.isValidHash(pending.nextDigest),
              pending.previousDigest.map(HelperPolicy.isValidHash) ?? true else { throw Failure.malformedPending }
        let current = try persistence.read("provisioning.signed.json")
        let currentDigest = current.map(SHA256Digest.hex)
        if currentDigest == pending.nextDigest, let current {
            let envelope = try decodeAndVerify(current)
            guard envelope.payload.bundleIdentifier == pending.bundleIdentifier,
                  envelope.payload.generation == pending.generation else { throw Failure.manualIntervention }
            let checkpoint = HelperProvisioningCheckpoint(generation: pending.generation, envelopeSHA256: pending.nextDigest)
            if let highest = try checkpointStore.highestCheckpoint(for: pending.bundleIdentifier.lowercased()) {
                guard pending.generation >= highest.generation else { throw Failure.rollbackDetected }
                if pending.generation == highest.generation && highest.envelopeSHA256 != pending.nextDigest {
                    throw Failure.rollbackDetected
                }
            }
            try checkpointStore.record(checkpoint, for: pending.bundleIdentifier.lowercased())
            try persistence.remove("provisioning.pending.json")
            return
        }
        if currentDigest == pending.previousDigest {
            try persistence.remove("provisioning.pending.json")
            return
        }
        throw Failure.manualIntervention
    }

    private func decodeAndVerify(_ data: Data) throws -> HelperSignedProvisioningManifest {
        guard let envelope = try? JSONDecoder().decode(HelperSignedProvisioningManifest.self, from: data) else { throw Failure.signatureInvalid }
        do { try verifier.verify(envelope); try envelope.payload.validate() }
        catch { throw Failure.signatureInvalid }
        return envelope
    }
}


/// Production checkpoint persistence is device-local Keychain only. Non-Apple builds fail closed.
enum HelperProvisioningCheckpointStoreFactory {
    enum Failure: Error { case persistentStoreUnavailable }
    static func make() throws -> HelperProvisioningCheckpointStoring {
        #if canImport(Security)
        return KeychainHelperProvisioningCheckpointStore()
        #else
        throw Failure.persistentStoreUnavailable
        #endif
    }
}
