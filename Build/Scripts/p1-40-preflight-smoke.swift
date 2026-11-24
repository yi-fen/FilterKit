import Foundation

enum HelperPolicy {
    static func isValidCDHash(_ value: String) -> Bool {
        value.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil
    }
}
struct HelperDeploymentManifest { let allowedHelperCDHashes: [String] }
struct HelperStartupRecoveryCheck {
    enum Detail: Equatable { case clean, legacyRecoveryRequired, threeFileRecoveryRequired, bothRecoveryRequired, invalidJournal }
    func inspectDetailed(pluginDirectory: String) -> Detail {
        FileManager.default.fileExists(atPath: pluginDirectory + "/pending.journal") ? .threeFileRecoveryRequired : .clean
    }
}
@main struct P140Smoke {
    static func main() throws {
        let pin = String(repeating: "b", count: 40)
        let verifier = HelperCodeSignatureVerifier()
        try verifier.verifyRunningHelper(cdHash: pin, allowedCDHashes: [pin])
        do { try verifier.verifyRunningHelper(cdHash: String(repeating: "c", count: 40), allowedCDHashes: [pin]); fatalError("mismatch accepted") }
        catch HelperCodeSignatureVerifier.VerificationError.runningCDHashMismatch { }
        do { try verifier.verifyRunningHelper(cdHash: pin, allowedCDHashes: []); fatalError("empty pins accepted") }
        catch HelperCodeSignatureVerifier.VerificationError.malformedExpectedCDHash { }

        let root = NSTemporaryDirectory() + "p140-smoke-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manifest = HelperDeploymentManifest(allowedHelperCDHashes: [pin])
        let preflight = HelperRuntimePreflight()
        let clean = try preflight.inspect(runningCDHash: pin, manifest: manifest, pluginDirectory: root)
        guard clean.helperIdentityVerified, clean.permitsNormalDeployment else { fatalError("clean preflight failed") }
        try Data("pending".utf8).write(to: URL(fileURLWithPath: root + "/pending.journal"))
        let pending = try preflight.inspect(runningCDHash: pin, manifest: manifest, pluginDirectory: root)
        guard pending.helperIdentityVerified, pending.recoveryDetail == .threeFileRecoveryRequired,
              !pending.permitsNormalDeployment else { fatalError("pending recovery did not block deployment") }
        guard FileManager.default.fileExists(atPath: root + "/pending.journal") else { fatalError("preflight mutated journal") }
        do { _ = try preflight.inspect(runningCDHash: String(repeating: "c", count: 40), manifest: manifest, pluginDirectory: root); fatalError("untrusted helper accepted") }
        catch HelperRuntimePreflight.Failure.identityRejected { }
        print("PASS: running Helper CDHash matches installer pin")
        print("PASS: mismatched and empty CDHash pins fail closed")
        print("PASS: clean read-only startup preflight permits deployment checks")
        print("PASS: pending journal is reported and blocks normal deployment without mutation")
        print("PASS: untrusted running Helper identity is rejected before recovery inspection")
    }
}
