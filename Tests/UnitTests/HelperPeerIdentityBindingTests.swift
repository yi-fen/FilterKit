import XCTest
@testable import FilterKit

final class HelperPeerIdentityBindingTests: XCTestCase {
    func testStableSocketCredentialsAreAccepted() {
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 123)
        XCTAssertTrue(HelperPeerIdentityBindingPolicy.credentialsAreStable(before: peer, after: peer))
    }

    func testChangedPIDIsRejected() {
        let before = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 123)
        let after = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 124)
        XCTAssertFalse(HelperPeerIdentityBindingPolicy.credentialsAreStable(before: before, after: after))
    }

    func testKernelAuditTokenEvidenceMustBeFullSHA256Hex() {
        let valid = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil,
            auditSessionID: 7, auditTokenDigest: String(repeating: "b", count: 64))
        let missing = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil,
            auditSessionID: 7)
        let truncated = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil,
            auditSessionID: 7, auditTokenDigest: "abcd")
        XCTAssertTrue(HelperPeerIdentityBindingPolicy.hasKernelAuditTokenEvidence(valid))
        XCTAssertFalse(HelperPeerIdentityBindingPolicy.hasKernelAuditTokenEvidence(missing))
        XCTAssertFalse(HelperPeerIdentityBindingPolicy.hasKernelAuditTokenEvidence(truncated))
    }

    func testIdentityMustMatchAllKernelSocketCredentials() {
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 123)
        let valid = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
                                       cdHashHex: String(repeating: "a", count: 40),
                                       pidVersion: nil, auditSessionID: nil)
        let wrongGID = HelperPeerIdentity(uid: 501, gid: 502, pid: 123,
                                          cdHashHex: String(repeating: "a", count: 40),
                                          pidVersion: nil, auditSessionID: nil)
        XCTAssertTrue(HelperPeerIdentityBindingPolicy.identity(valid, matches: peer))
        XCTAssertFalse(HelperPeerIdentityBindingPolicy.identity(wrongGID, matches: peer))
    }

    func testPIDGenerationMustBePresentAndStable() {
        XCTAssertTrue(HelperPeerProcessGenerationBindingPolicy.isStable(before: 77, after: 77))
        XCTAssertFalse(HelperPeerProcessGenerationBindingPolicy.isStable(before: nil, after: 77))
        XCTAssertFalse(HelperPeerProcessGenerationBindingPolicy.isStable(before: 77, after: nil))
        XCTAssertFalse(HelperPeerProcessGenerationBindingPolicy.isStable(before: 77, after: 78))
        XCTAssertFalse(HelperPeerProcessGenerationBindingPolicy.isStable(before: 0, after: 0))
    }

    func testDarwinEvidenceRequiresBothAuditTokenAndPIDGeneration() {
        let complete = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: 9,
            auditSessionID: 7, auditTokenDigest: String(repeating: "b", count: 64))
        let noGeneration = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil,
            auditSessionID: 7, auditTokenDigest: String(repeating: "b", count: 64))
        XCTAssertTrue(HelperPeerIdentityBindingPolicy.hasCompleteDarwinProcessGenerationEvidence(complete))
        XCTAssertFalse(HelperPeerIdentityBindingPolicy.hasCompleteDarwinProcessGenerationEvidence(noGeneration))
    }


    func testConcurrentPIDGenerationPolicyStress() {
        let failures = DispatchQueue(label: "filterkit.p217.policy-stress")
        var rejectedStablePairs = 0
        var acceptedChangedPairs = 0
        DispatchQueue.concurrentPerform(iterations: 10_000) { index in
            let generation = UInt64((index % 97) + 1)
            if !HelperPeerProcessGenerationBindingPolicy.isStable(before: generation, after: generation) {
                failures.sync { rejectedStablePairs += 1 }
            }
            if HelperPeerProcessGenerationBindingPolicy.isStable(before: generation, after: generation + 1) {
                failures.sync { acceptedChangedPairs += 1 }
            }
        }
        XCTAssertEqual(rejectedStablePairs, 0)
        XCTAssertEqual(acceptedChangedPairs, 0)
    }


    func testAuthenticationDiagnosticExposesEvidenceWithoutTokenDigest() {
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: 9,
            auditSessionID: 7, auditTokenDigest: String(repeating: "b", count: 64))
        let diagnostic = HelperPeerAuthenticationDiagnostic(stage: .codeIdentity,
            outcome: .accepted, identity: identity, reasonCode: "peer_identity_accepted")
        XCTAssertEqual(diagnostic.pidVersion, 9)
        XCTAssertEqual(diagnostic.auditSessionID, 7)
        XCTAssertTrue(diagnostic.hasAuditTokenEvidence)
        XCTAssertTrue(diagnostic.hasProcessGenerationEvidence)
        let encoded = try! JSONEncoder().encode(diagnostic)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains(String(repeating: "b", count: 64)))
    }

    func testAuthenticationDiagnosticMarksIncompleteEvidence() {
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil,
            auditSessionID: nil, auditTokenDigest: String(repeating: "b", count: 64))
        let diagnostic = HelperPeerAuthenticationDiagnostic(stage: .codeIdentity,
            outcome: .rejected, identity: identity, reasonCode: "peer_identity_rejected")
        XCTAssertTrue(diagnostic.hasAuditTokenEvidence)
        XCTAssertFalse(diagnostic.hasProcessGenerationEvidence)
        XCTAssertNil(diagnostic.pidVersion)
    }


    func testAuthenticationLifecycleRequiresOrderedStages() throws {
        let lifecycle = HelperPeerAuthenticationLifecycle()
        XCTAssertThrowsError(try lifecycle.advance(to: .trustVerified))
        try lifecycle.advance(to: .credentialsVerified)
        try lifecycle.advance(to: .codeIdentityVerified)
        try lifecycle.advance(to: .trustVerified)
        try lifecycle.advance(to: .handshakeVerified)
        try lifecycle.advance(to: .authenticated)
        XCTAssertEqual(lifecycle.currentState(), .authenticated)
    }

    func testAuthenticationFailureAndCleanupAreTerminalAndIdempotent() throws {
        let lifecycle = HelperPeerAuthenticationLifecycle()
        try lifecycle.advance(to: .credentialsVerified)
        lifecycle.fail()
        lifecycle.fail()
        XCTAssertEqual(lifecycle.currentState(), .failed)
        lifecycle.close()
        lifecycle.close()
        lifecycle.fail()
        XCTAssertEqual(lifecycle.currentState(), .closed)
        XCTAssertThrowsError(try lifecycle.advance(to: .credentialsVerified))
    }

    func testConcurrentConnectionsHaveIsolatedAuthenticationState() {
        let count = 256
        let lock = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let lifecycle = HelperPeerAuthenticationLifecycle()
            do {
                try lifecycle.advance(to: .credentialsVerified)
                if index.isMultiple(of: 2) {
                    lifecycle.fail()
                    lifecycle.close()
                    guard lifecycle.currentState() == .closed else { throw HelperPeerAuthenticationLifecycle.LifecycleError.invalidTransition(.closed, .failed) }
                } else {
                    try lifecycle.advance(to: .codeIdentityVerified)
                    try lifecycle.advance(to: .trustVerified)
                    try lifecycle.advance(to: .handshakeVerified)
                    try lifecycle.advance(to: .authenticated)
                    guard lifecycle.currentState() == .authenticated else { throw HelperPeerAuthenticationLifecycle.LifecycleError.invalidTransition(.authenticated, .failed) }
                    lifecycle.close()
                }
            } catch {
                lock.lock(); failures += 1; lock.unlock()
            }
        }
        XCTAssertEqual(failures, 0)
    }

}
