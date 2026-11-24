import Foundation

/// Verifies the exact staged bytes against the release hand-off. This is integrity checking,
/// not code-signature or release-provenance verification; those remain trusted-installer duties.
struct HelperInstallerReleaseVerifier {
    enum VerificationError: Error, Equatable {
        case invalidBundle, missingArtifact, unexpectedArtifact, digestMismatch
        case invalidLaunchDaemon, executableTooSmall
    }

    struct VerifiedRelease: Equatable {
        let releaseIdentifier: String
        let executableSHA256: String
        let launchDaemonSHA256: String
        let executableByteCount: Int
    }

    func verify(bundle: HelperInstallerProvisioningBundle,
                artifacts: [String: Data],
                expectedDigests: [HelperInstallerArtifactDigest]) throws -> VerifiedRelease {
        do { try bundle.validate() } catch { throw VerificationError.invalidBundle }
        let executablePath = "usr/libexec/filterkit-helper"
        let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
        let required = Set([executablePath, launchDaemonPath])
        guard Set(artifacts.keys) == required else {
            if required.subtracting(artifacts.keys).isEmpty { throw VerificationError.unexpectedArtifact }
            throw VerificationError.missingArtifact
        }
        let digestMap = Dictionary(expectedDigests.map { ($0.relativePath, $0.sha256.lowercased()) },
                                   uniquingKeysWith: { first, _ in first })
        guard expectedDigests.count == 2, Set(digestMap.keys) == required,
              expectedDigests.allSatisfy({ $0.validate() }) else {
            throw VerificationError.missingArtifact
        }
        guard let executable = artifacts[executablePath], executable.count >= 4,
              let launchData = artifacts[launchDaemonPath] else { throw VerificationError.executableTooSmall }
        let executableHash = SHA256Digest.hex(executable)
        let launchHash = SHA256Digest.hex(launchData)
        guard digestMap[executablePath] == executableHash,
              digestMap[launchDaemonPath] == launchHash else { throw VerificationError.digestMismatch }

        guard let plist = try? PropertyListSerialization.propertyList(from: launchData, options: [], format: nil) as? [String: Any],
              plist["Label"] as? String == "cn.yfen.filterkit.helper",
              (plist["ProgramArguments"] as? [String]) == [bundle.jbRootPath + "/usr/libexec/filterkit-helper"],
              plist["Disabled"] as? Bool == true,
              plist["RunAtLoad"] as? Bool == false,
              plist["KeepAlive"] as? Bool == false else {
            throw VerificationError.invalidLaunchDaemon
        }
        return VerifiedRelease(releaseIdentifier: bundle.releaseIdentifier,
            executableSHA256: executableHash, launchDaemonSHA256: launchHash,
            executableByteCount: executable.count)
    }
}
