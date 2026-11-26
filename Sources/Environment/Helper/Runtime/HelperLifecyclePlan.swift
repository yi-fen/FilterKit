import Foundation

struct HelperLifecycleArtifact: Equatable {
    enum Kind: String { case executable, launchDaemonPlist, manifest, ipcParentDirectory, auditDirectory, socket }
    let kind: Kind
    let absolutePath: String
    let owner: String
    let modeOctal: String
}

struct HelperLifecyclePlan: Equatable {
    enum Action: String { case install, start, stop, uninstall, repin }
    let action: Action
    let jbRoot: String
    let artifacts: [HelperLifecycleArtifact]
    let requiresRootInstaller: Bool
    let requiresFreshCDHashes: Bool
    let mayRunFromApp: Bool

    static func make(action: Action, jbRoot: String, executableCDHash: String? = nil,
                     appCDHash: String? = nil, socketGroupID: UInt32 = 501) throws -> Self {
        guard HelperPolicy.isAbsoluteCleanPath(jbRoot),
              jbRoot != "/",
              (executableCDHash == nil || HelperPolicy.isValidCDHash(executableCDHash!)),
              (appCDHash == nil || HelperPolicy.isValidCDHash(appCDHash!)), socketGroupID != 0 else {
            throw HelperLifecyclePlanError.invalidRootOrFingerprint
        }
        let base = jbRoot + "/Library/FilterKit/Helper"
        let artifacts = [
            HelperLifecycleArtifact(kind: .executable, absolutePath: jbRoot + "/usr/libexec/filterkit-helper", owner: "root:wheel", modeOctal: "0755"),
            HelperLifecycleArtifact(kind: .launchDaemonPlist, absolutePath: jbRoot + "/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist", owner: "root:wheel", modeOctal: "0644"),
            HelperLifecycleArtifact(kind: .ipcParentDirectory, absolutePath: jbRoot + "/Library/FilterKit", owner: "root:wheel", modeOctal: "0711"),
            HelperLifecycleArtifact(kind: .manifest, absolutePath: base + "/manifest.json", owner: "root:wheel", modeOctal: "0600"),
            HelperLifecycleArtifact(kind: .auditDirectory, absolutePath: base, owner: "root:wheel", modeOctal: "0711"),
            HelperLifecycleArtifact(kind: .socket, absolutePath: base + "/helper.sock", owner: "root:\(socketGroupID)", modeOctal: "0660")
        ]
        return Self(action: action, jbRoot: jbRoot, artifacts: artifacts,
                    requiresRootInstaller: true, requiresFreshCDHashes: action == .repin || action == .install,
                    mayRunFromApp: false)
    }
}

enum HelperLifecyclePlanError: Error, Equatable { case invalidRootOrFingerprint }
