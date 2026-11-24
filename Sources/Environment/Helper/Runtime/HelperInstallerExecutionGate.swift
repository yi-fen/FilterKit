import Foundation

/// Explicit release gate. No production Root Installer adapter exists in this phase, so every
/// real execution request is rejected before a platform operation can be reached.
struct HelperInstallerExecutionGate {
    enum BlockReason: String, Equatable {
        case planNotReleased, rootInstallerUnavailable, provenanceNotVerified
        case signedArtifactsNotVerified, operatorApprovalMissing
    }
    struct Evidence {
        let rootInstallerAvailable: Bool
        let releaseProvenanceVerified: Bool
        let signedArtifactsVerified: Bool
        let operatorApproved: Bool
    }

    func blockReason(plan: HelperInstallerTransactionPlan, evidence: Evidence) -> BlockReason? {
        guard plan.executionEnabled else { return .planNotReleased }
        guard evidence.rootInstallerAvailable else { return .rootInstallerUnavailable }
        guard evidence.releaseProvenanceVerified else { return .provenanceNotVerified }
        guard evidence.signedArtifactsVerified else { return .signedArtifactsNotVerified }
        guard evidence.operatorApproved else { return .operatorApprovalMissing }
        return nil
    }
}
