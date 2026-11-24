import Foundation

func require137(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-37", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P137ReleaseSetSmoke {
    static func main() throws {
        let bundle = HelperInstallerProvisioningBundle(schemaVersion: 1, generation: 12,
            releaseIdentifier: "1.0.0-p137", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "a", count: 40),
            helperCDHash: String(repeating: "b", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "dopamine-roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
        let executable = Data([0xcf, 0xfa, 0xed, 0xfe, 1, 2, 3, 4])
        let manifest = try JSONEncoder().encode(bundle.disabledRootManifest())
        let launch = try bundle.disabledLaunchDaemonPlist()
        let artifacts = [HelperRootReleaseSet.executablePath: executable,
                         HelperRootReleaseSet.manifestPath: manifest,
                         HelperRootReleaseSet.launchDaemonPath: launch]
        let digests = artifacts.map { HelperInstallerArtifactDigest(relativePath: $0.key, sha256: SHA256Digest.hex($0.value)) }
        let verified = try HelperRootReleaseSet().verify(bundle: bundle, artifacts: artifacts, expectedDigests: digests)
        try require137(verified.hashes.count == 3, "three-artifact inventory not verified")

        var altered = artifacts; altered[HelperRootReleaseSet.manifestPath] = Data("{}".utf8)
        do {
            _ = try HelperRootReleaseSet().verify(bundle: bundle, artifacts: altered, expectedDigests: digests)
            throw NSError(domain: "P1-37", code: 2, userInfo: [NSLocalizedDescriptionKey: "altered manifest accepted"])
        } catch is HelperRootReleaseSet.VerificationError { }

        let newHashes = verified.hashes
        let oldHashes: [HelperRootReleaseSet.Artifact: String?] = [.executable: nil, .deploymentManifest: nil, .launchDaemon: nil]
        let clean = HelperRootReleaseRecoveryAssessment.Snapshot(
            executable: .init(currentHash: nil, previousBackupHash: nil, currentOwnedByFilterKit: false, backupOwnedByFilterKit: false),
            manifest: .init(currentHash: nil, previousBackupHash: nil, currentOwnedByFilterKit: false, backupOwnedByFilterKit: false),
            launchDaemon: .init(currentHash: nil, previousBackupHash: nil, currentOwnedByFilterKit: false, backupOwnedByFilterKit: false))
        let resume = HelperRootReleaseRecoveryAssessment.assess(state: .artifactsVerified, newHashes: newHashes, previousHashes: oldHashes, snapshot: clean)
        try require137(resume.decision == .resumeActivation, "install recovery should resume only from verified clean state")
        let unknown = HelperRootReleaseRecoveryAssessment.Snapshot(
            executable: .init(currentHash: String(repeating: "f", count: 64), previousBackupHash: nil, currentOwnedByFilterKit: true, backupOwnedByFilterKit: false),
            manifest: clean.manifest, launchDaemon: clean.launchDaemon)
        let manual = HelperRootReleaseRecoveryAssessment.assess(state: .staged, newHashes: newHashes, previousHashes: oldHashes, snapshot: unknown)
        try require137(manual.decision == .manualIntervention, "unknown file hash must require manual intervention")
        print("PASS: exact helper executable, disabled deployment manifest and disabled launchd plist verified")
        print("PASS: altered deployment manifest rejected")
        print("PASS: clean interrupted first-install state assessed without mutation")
        print("PASS: unknown destination hash fails closed to manual intervention")
    }
}
