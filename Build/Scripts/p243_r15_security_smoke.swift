import Foundation

enum HelperPolicy {
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
}
struct HelperInstallerServiceObservation: Equatable {
    enum State: Equatable { case running(pid: Int32, executableSHA256: String), stopped, unknown }
    let launchDaemonLabel: String; let observerCodeIdentitySHA256: String; let state: State
    func validates(expectedObserverCodeIdentitySHA256: String, expectedExecutableSHA256: String) -> Bool {
        guard launchDaemonLabel == "cn.yfen.filterkit.helper", observerCodeIdentitySHA256 == expectedObserverCodeIdentitySHA256 else { return false }
        switch state {
        case .running(let pid, let hash): return pid > 0 && hash == expectedExecutableSHA256
        case .stopped: return true
        case .unknown: return false
        }
    }
}
struct HelperPeerIdentity {
    let uid: UInt32; let pid: Int32; let cdHashHex: String; let auditTokenDigest: String?
    let verifiedCodeIdentifier: String?; let verifiedTeamIdentifier: String?
}
enum HelperPeerIdentityBindingPolicy {
    static func codeSigningIdentityMatches(_ identity: HelperPeerIdentity, bundleIdentifier: String, teamIdentifier: String) -> Bool {
        identity.verifiedCodeIdentifier == bundleIdentifier && identity.verifiedTeamIdentifier == teamIdentifier
    }
}
func check(_ value: @autoclosure () -> Bool, _ label: String) { if !value() { fatalError("FAIL: \(label)") }; print("PASS: \(label)") }
let challenge = UUID()
let pin = HelperInstallerAuthenticatedServiceObserver.Pin(bundleIdentifier: "cn.yfen.filterkit.observer", teamIdentifier: "ABCDE12345", cdHash: String(repeating: "a", count: 40), observerCodeIdentitySHA256: String(repeating: "b", count: 64), auditUID: 0)
let peer = HelperPeerIdentity(uid: 0, pid: 77, cdHashHex: pin.cdHash, auditTokenDigest: String(repeating: "c", count: 64), verifiedCodeIdentifier: pin.bundleIdentifier, verifiedTeamIdentifier: pin.teamIdentifier)
let observation = HelperInstallerServiceObservation(launchDaemonLabel: "cn.yfen.filterkit.helper", observerCodeIdentitySHA256: pin.observerCodeIdentitySHA256, state: .stopped)
let report = HelperInstallerAuthenticatedServiceObserver.Report(challenge: challenge, observation: observation)
let accepted = try HelperInstallerAuthenticatedServiceObserver.validate(report: report, expectedChallenge: challenge, authenticatedPeer: peer, pin: pin, expectedHelperExecutableSHA256: String(repeating: "d", count: 64))
check(accepted == observation, "authenticated fresh observer report accepted")
do { _ = try HelperInstallerAuthenticatedServiceObserver.validate(report: report, expectedChallenge: UUID(), authenticatedPeer: peer, pin: pin, expectedHelperExecutableSHA256: String(repeating: "d", count: 64)); fatalError("stale challenge accepted") } catch HelperInstallerAuthenticatedServiceObserver.ObserverError.challengeMismatch { check(true, "stale challenge rejected") }
let unverified = HelperPeerIdentity(uid: 0, pid: 77, cdHashHex: pin.cdHash, auditTokenDigest: nil, verifiedCodeIdentifier: nil, verifiedTeamIdentifier: nil)
do { _ = try HelperInstallerAuthenticatedServiceObserver.validate(report: report, expectedChallenge: challenge, authenticatedPeer: unverified, pin: pin, expectedHelperExecutableSHA256: String(repeating: "d", count: 64)); fatalError("unverified peer accepted") } catch HelperInstallerAuthenticatedServiceObserver.ObserverError.peerIdentityUnverified { check(true, "unverified peer rejected") }
for point in HelperInstallerCrashInjectionMatrix.Point.allCases {
    check(HelperInstallerCrashInjectionMatrix.disposition(for: point) != .verifyAllArtifactsAndPointer || point == .afterJournalCompletionSync, "crash disposition defined: \(point.rawValue)")
}
check(!HelperInstallerCrashInjectionMatrix.productionInjectionEnabled, "production crash injection remains disabled")
