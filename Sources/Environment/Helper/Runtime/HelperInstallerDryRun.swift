import Foundation
/// Validation-only boundary for the future privileged installer. It never writes files,
/// changes ownership, invokes launchctl, or modifies the running Helper.
struct HelperInstallerDryRun {
    enum DryRunError: Error, Equatable { case invalidBundle, invalidArtifactDigest, repinBaselineRequired, invalidRepinTransition }

    func validate(bundle: HelperInstallerProvisioningBundle,
                  artifactDigests: [HelperInstallerArtifactDigest],
                  action: HelperInstallerTransactionPlan.Action,
                  trustedBaseline: HelperVerifiedProvisioningBaseline? = nil) throws -> HelperInstallerDryRunReport {
        // Deliberately unprivileged: this API validates and renders artifacts only.
        // The production installer must independently enforce root and signed-package provenance.
        try bundle.validate()
        if action == .repin {
            guard let trustedBaseline else { throw DryRunError.repinBaselineRequired }
            do {
                try HelperClientCodeIdentityRotationPolicy.validate(previous: trustedBaseline.payload, next: bundle)
            } catch {
                throw DryRunError.invalidRepinTransition
            }
        }
        let artifactPaths = Set(artifactDigests.map(\.relativePath))
        guard !artifactDigests.isEmpty, artifactDigests.allSatisfy({ $0.validate() }),
              artifactPaths.count == artifactDigests.count,
              artifactPaths.contains("usr/libexec/filterkit-helper"),
              artifactPaths.contains("Library/LaunchDaemons/cn.yfen.filterkit.helper.plist") else {
            throw DryRunError.invalidArtifactDigest
        }
        let plan = try HelperInstallerTransactionPlan.make(action: action, bundle: bundle)
        let manifest = try bundle.disabledRootManifest()
        let appTrust = try bundle.appTrustConfiguration()
        let launchd = try bundle.disabledLaunchDaemonPlist()
        return HelperInstallerDryRunReport(releaseIdentifier: bundle.releaseIdentifier,
            generation: bundle.generation, action: action, plan: plan,
            appTrustConfiguration: appTrust, rootManifest: manifest,
            launchDaemonPlist: launchd, artifactDigests: artifactDigests,
            writesPerformed: false, launchdInvoked: false, executionEnabled: false)
    }
}

struct HelperInstallerDryRunReport {
    let releaseIdentifier: String
    let generation: UInt64
    let action: HelperInstallerTransactionPlan.Action
    let plan: HelperInstallerTransactionPlan
    let appTrustConfiguration: HelperAppTrustConfiguration
    let rootManifest: HelperDeploymentManifest
    let launchDaemonPlist: Data
    let artifactDigests: [HelperInstallerArtifactDigest]
    let writesPerformed: Bool
    let launchdInvoked: Bool
    let executionEnabled: Bool
}
