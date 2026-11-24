import XCTest
@testable import FilterKit
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

final class HelperApplePlatformReleaseTests: XCTestCase {
    #if canImport(CryptoKit)
    /// RFC 8032, Ed25519 test vector 1 (empty message). This exercises Apple's real CryptoKit
    /// implementation rather than the deterministic signature-checking test double.
    func testCryptoKitEd25519RFC8032VectorAndTamperRejection() throws {
        let publicKey = try XCTUnwrap(Data(hex: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"))
        let signature = try XCTUnwrap(Data(hex: "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"))
        let checker = HelperEd25519SignatureChecker()
        XCTAssertTrue(checker.verify(signature: signature, message: Data(), publicKey: publicKey))
        var tampered = signature
        tampered[0] ^= 0x01
        XCTAssertFalse(checker.verify(signature: tampered, message: Data(), publicKey: publicKey))
        XCTAssertFalse(checker.verify(signature: signature, message: Data([0x00]), publicKey: publicKey))
    }
    #endif

    #if canImport(Security)
    func testKeychainGenerationLedgerPersistsAndRejectsRollback() throws {
        let service = "cn.yfen.filterkit.tests.generation.\(UUID().uuidString)"
        let store = KeychainHelperReleaseGenerationStore(service: service)
        XCTAssertNil(try store.highestAcceptedGeneration(for: "cn.yfen.filterkit.helper"))
        try store.recordAcceptedGeneration(10, for: "cn.yfen.filterkit.helper")
        try store.recordAcceptedGeneration(12, for: "cn.yfen.filterkit.helper")
        XCTAssertEqual(try store.highestAcceptedGeneration(for: "cn.yfen.filterkit.helper"), 12)
        XCTAssertThrowsError(try store.recordAcceptedGeneration(11, for: "cn.yfen.filterkit.helper"))
        let reopened = KeychainHelperReleaseGenerationStore(service: service)
        XCTAssertEqual(try reopened.highestAcceptedGeneration(for: "cn.yfen.filterkit.helper"), 12)
    }

    func testKeychainAppendOnlyLedgerRemainsMonotonicUnderConcurrentWriters() throws {
        let service = "cn.yfen.filterkit.tests.concurrent-generation.\(UUID().uuidString)"
        let bundle = "cn.yfen.filterkit.helper"
        let unexpected = LockedTestFailures()
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            do {
                try KeychainHelperReleaseGenerationStore(service: service)
                    .recordAcceptedGeneration(UInt64(index + 1), for: bundle)
            } catch HelperReleaseAntiRollbackGuard.Failure.rollbackDetected {
                // Expected when a lower generation races after a higher generation was recorded.
            } catch {
                unexpected.append(String(describing: error))
            }
        }
        XCTAssertTrue(unexpected.values.isEmpty, unexpected.values.joined(separator: "; "))
        XCTAssertEqual(try KeychainHelperReleaseGenerationStore(service: service)
            .highestAcceptedGeneration(for: bundle), 32)
    }
    #endif
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

private final class LockedTestFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
