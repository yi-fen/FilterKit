import Foundation

enum HelperPolicy {
    static func isValidCDHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil }
}
struct HelperInstallerProvisioningBundle {
    let releaseIdentifier: String; let generation: UInt64; let bundleIdentifier: String
    let helperVersion: String; let helperCDHash: String
    func validate() throws {}
}
@main struct P141Smoke {
    static func main() throws {
        let cd = String(repeating: "a", count: 40), sha = String(repeating: "b", count: 64)
        let bundle = HelperInstallerProvisioningBundle(releaseIdentifier: "release-41", generation: 41,
            bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.1", helperCDHash: cd)
        let manifest = HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-41", generation: 41,
            bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.1", helperCDHash: cd,
            helperSHA256: sha, publisherPolicy: .integrityOnly, teamIdentifier: nil, leafCertificateSHA256: nil)
        try manifest.validate()
        guard manifest.matches(bundle) else { fatalError("matching provisioning rejected") }
        let verifier = HelperReleaseTrustVerifier()
        try verifier.verify(manifest: manifest, provisioning: bundle, observedHelperSHA256: sha, runningCDHash: cd)
        do { try verifier.verify(manifest: manifest, provisioning: bundle, observedHelperSHA256: String(repeating: "c", count: 64), runningCDHash: cd); fatalError("wrong SHA accepted") }
        catch HelperReleaseTrustVerifier.Failure.helperDigestMismatch {}
        do { try verifier.verify(manifest: manifest, provisioning: bundle, observedHelperSHA256: sha, runningCDHash: String(repeating: "d", count: 40)); fatalError("wrong CDHash accepted") }
        catch HelperReleaseTrustVerifier.Failure.helperCDHashMismatch {}
        let publisher = HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-41", generation: 41,
            bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.1", helperCDHash: cd,
            helperSHA256: sha, publisherPolicy: .pinnedAppleIdentity, teamIdentifier: nil, leafCertificateSHA256: nil)
        do { try publisher.validate(); fatalError("incomplete publisher pins accepted") }
        catch HelperReleaseTrustManifest.ValidationError.incompletePublisherPins {}
        let pinned = HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-41", generation: 41,
            bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.1", helperCDHash: cd,
            helperSHA256: sha, publisherPolicy: .pinnedAppleIdentity, teamIdentifier: "ABCDE12345",
            leafCertificateSHA256: String(repeating: "e", count: 64))
        try pinned.validate()
        do { try verifier.verify(manifest: pinned, provisioning: bundle, observedHelperSHA256: sha,
              runningCDHash: cd, observedTeamIdentifier: "ZZZZZ12345",
              observedLeafCertificateSHA256: String(repeating: "e", count: 64)); fatalError("wrong Team ID accepted") }
        catch HelperReleaseTrustVerifier.Failure.teamIdentifierMismatch {}
        do { try verifier.verify(manifest: pinned, provisioning: bundle, observedHelperSHA256: sha,
              runningCDHash: cd); fatalError("missing publisher evidence accepted") }
        catch HelperReleaseTrustVerifier.Failure.publisherIdentityUnavailable {}
        print("PASS: release trust manifest schema and provisioning binding")
        print("PASS: helper SHA-256 and running CDHash enforcement")
        print("PASS: publisher pin policy rejects incomplete Team ID/certificate pins")
        print("PASS: Team ID mismatch and missing publisher evidence rejected")
    }
}
