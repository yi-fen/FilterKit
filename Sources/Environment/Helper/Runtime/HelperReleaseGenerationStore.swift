import Foundation

/// Persistence boundary for anti-rollback state. Production implementations must use a
/// root-owned, no-follow, atomic store and must fail closed if the state is absent or corrupt.
protocol HelperReleaseGenerationStoring {
    func highestAcceptedGeneration(for bundleIdentifier: String) throws -> UInt64?
    func recordAcceptedGeneration(_ generation: UInt64, for bundleIdentifier: String) throws
}

struct HelperReleaseAntiRollbackGuard {
    enum Failure: Error, Equatable { case invalidBundleIdentifier, rollbackDetected, generationNotIncreasing }
    let store: HelperReleaseGenerationStoring

    func check(_ manifest: HelperReleaseTrustManifest) throws {
        try manifest.validate()
        guard manifest.bundleIdentifier.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else {
            throw Failure.invalidBundleIdentifier
        }
        if let highest = try store.highestAcceptedGeneration(for: manifest.bundleIdentifier), manifest.generation < highest {
            throw Failure.rollbackDetected
        }
    }

    func accept(_ manifest: HelperReleaseTrustManifest) throws {
        try check(manifest)
        if let highest = try store.highestAcceptedGeneration(for: manifest.bundleIdentifier), manifest.generation <= highest {
            if manifest.generation == highest { return } // idempotent revalidation of the same release generation
            throw Failure.generationNotIncreasing
        }
        try store.recordAcceptedGeneration(manifest.generation, for: manifest.bundleIdentifier)
    }
}

/// Test/development implementation only; it does not survive process restart.
final class InMemoryHelperReleaseGenerationStore: HelperReleaseGenerationStoring {
    private var values: [String: UInt64] = [:]
    func highestAcceptedGeneration(for bundleIdentifier: String) throws -> UInt64? { values[bundleIdentifier] }
    func recordAcceptedGeneration(_ generation: UInt64, for bundleIdentifier: String) throws {
        if let old = values[bundleIdentifier], generation < old { throw HelperReleaseAntiRollbackGuard.Failure.rollbackDetected }
        values[bundleIdentifier] = generation
    }
}

#if canImport(Security)
import Security

/// Device-local append-only Keychain generation ledger.
/// Each accepted generation is a distinct immutable Keychain item. Concurrent processes can
/// add entries, but cannot overwrite a higher generation with a stale lower value. This is
/// stronger than a read/modify/write singleton item, though it is not a hardware monotonic counter.
final class KeychainHelperReleaseGenerationStore: HelperReleaseGenerationStoring {
    enum StoreError: Error { case invalidBundleIdentifier, keychain(OSStatus), malformedValue }
    private let service: String
    private let lock = NSLock()

    init(service: String = "cn.yfen.filterkit.release-generation") { self.service = service }

    func highestAcceptedGeneration(for bundleIdentifier: String) throws -> UInt64? {
        guard Self.valid(bundleIdentifier) else { throw StoreError.invalidBundleIdentifier }
        lock.lock(); defer { lock.unlock() }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            throw StoreError.keychain(status)
        }
        let prefix = Self.accountPrefix(bundleIdentifier)
        var highest: UInt64?
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            if account == bundleIdentifier {
                // Read-only migration support for the former singleton record.
                guard let data = row[kSecValueData as String] as? Data, data.count == 8 else {
                    throw StoreError.malformedValue
                }
                highest = max(highest ?? 0, Self.decode(data))
            } else if account.hasPrefix(prefix) {
                let suffix = account.dropFirst(prefix.count)
                guard let generation = UInt64(suffix), generation > 0 else { throw StoreError.malformedValue }
                highest = max(highest ?? 0, generation)
            }
        }
        return highest
    }

    func recordAcceptedGeneration(_ generation: UInt64, for bundleIdentifier: String) throws {
        guard Self.valid(bundleIdentifier), generation > 0 else { throw StoreError.invalidBundleIdentifier }
        lock.lock(); defer { lock.unlock() }
        if let current = try highestAcceptedGenerationUnlocked(for: bundleIdentifier), generation < current {
            throw HelperReleaseAntiRollbackGuard.Failure.rollbackDetected
        }
        let account = Self.accountPrefix(bundleIdentifier) + String(format: "%020llu", generation)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        var value = generation.bigEndian
        let data = withUnsafeBytes(of: &value) { Data($0) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw StoreError.keychain(status) }
    }

    /// Avoid recursively acquiring the process lock while preserving the same append-only scan.
    private func highestAcceptedGenerationUnlocked(for bundleIdentifier: String) throws -> UInt64? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnAttributes as String: true,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else { throw StoreError.keychain(status) }
        let prefix = Self.accountPrefix(bundleIdentifier)
        var highest: UInt64?
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            if account == bundleIdentifier {
                guard let data = row[kSecValueData as String] as? Data, data.count == 8 else { throw StoreError.malformedValue }
                highest = max(highest ?? 0, Self.decode(data))
            } else if account.hasPrefix(prefix) {
                let suffix = account.dropFirst(prefix.count)
                guard let generation = UInt64(suffix), generation > 0 else { throw StoreError.malformedValue }
                highest = max(highest ?? 0, generation)
            }
        }
        return highest
    }

    private static func accountPrefix(_ bundleIdentifier: String) -> String { bundleIdentifier + "|generation|" }
    private static func decode(_ data: Data) -> UInt64 {
        data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
    private static func valid(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9.-]{3,255}$", options: .regularExpression) != nil
    }
}
#endif
