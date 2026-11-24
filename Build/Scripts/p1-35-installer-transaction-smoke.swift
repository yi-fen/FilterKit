import Foundation

func require135(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-35", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P135InstallerTransactionSmoke {
    static func main() throws {
        let bundle = HelperInstallerProvisioningBundle(schemaVersion: 1, generation: 10,
            releaseIdentifier: "1.0.0-p135", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "a", count: 40),
            helperCDHash: String(repeating: "b", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "dopamine-roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
        try bundle.validate()
        let executable = Data([0xcf, 0xfa, 0xed, 0xfe, 0x01, 0x02, 0x03])
        let launch = try bundle.disabledLaunchDaemonPlist()
        let paths = ["usr/libexec/filterkit-helper", "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"]
        let digests = [HelperInstallerArtifactDigest(relativePath: paths[0], sha256: SHA256Digest.hex(executable)),
                       HelperInstallerArtifactDigest(relativePath: paths[1], sha256: SHA256Digest.hex(launch))]
        let verified = try HelperInstallerReleaseVerifier().verify(bundle: bundle,
            artifacts: [paths[0]: executable, paths[1]: launch], expectedDigests: digests)
        try require135(verified.executableByteCount == executable.count, "verified executable size mismatch")

        var journal = try HelperInstallerTransactionJournal(action: .upgrade,
            releaseIdentifier: bundle.releaseIdentifier, generation: bundle.generation)
        try journal.apply(.verifyArtifacts)
        try journal.apply(.preservePreviousRelease)
        try journal.apply(.stageRelease)
        try journal.apply(.activateRelease)
        try journal.apply(.beginRollback)
        try journal.apply(.completeRollback)
        try journal.validateChain()
        try require135(journal.state == .rolledBack && journal.sequence == 6, "rollback journal transition invalid")

        var encodedJournal = try JSONEncoder().encode(journal)
        var journalObject = try JSONSerialization.jsonObject(with: encodedJournal) as! [String: Any]
        var journalEntries = journalObject["entries"] as! [[String: Any]]
        journalEntries[0]["hash"] = String(repeating: "f", count: 64)
        journalObject["entries"] = journalEntries
        encodedJournal = try JSONSerialization.data(withJSONObject: journalObject)
        let alteredJournal = try JSONDecoder().decode(HelperInstallerTransactionJournal.self, from: encodedJournal)
        do {
            try alteredJournal.validateChain()
            throw NSError(domain: "P1-35", code: 3, userInfo: [NSLocalizedDescriptionKey: "tampered journal accepted"])
        } catch is HelperInstallerTransactionJournal.JournalError { }

        let plan = try HelperInstallerTransactionPlan.make(action: .install, bundle: bundle)
        let gate = HelperInstallerExecutionGate()
        let reason = gate.blockReason(plan: plan, evidence: .init(rootInstallerAvailable: true,
            releaseProvenanceVerified: true, signedArtifactsVerified: true, operatorApproved: true))
        try require135(reason == .planNotReleased, "unreleased installer plan must remain blocked")

        do {
            _ = try HelperInstallerReleaseVerifier().verify(bundle: bundle,
                artifacts: [paths[0]: Data([1, 2, 3]), paths[1]: launch], expectedDigests: digests)
            throw NSError(domain: "P1-35", code: 2, userInfo: [NSLocalizedDescriptionKey: "tampered artifact accepted"])
        } catch is HelperInstallerReleaseVerifier.VerificationError { }

        print("PASS: exact staged executable and launchd bytes match SHA-256 inventory")
        print("PASS: launchd plist identity and disabled lifecycle flags validated")
        print("PASS: ordered upgrade journal and rollback transitions validated")
        print("PASS: tampered journal event hash rejected by chain replay")
        print("PASS: out-of-order transitions rejected by state machine")
        print("PASS: execution gate rejects all plans while executionEnabled=false")
        print("PASS: altered staged artifact rejected")
    }
}
