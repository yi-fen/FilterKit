import Foundation

/// Explicit review-stage authorization model. No case in this type authorizes filesystem writes,
/// launchd control, or service start. Production execution remains blocked by the existing gate.
struct HelperInstallerRecoveryAuthorization {
    enum Decision: Equatable {
        case evidenceOnly
        case reviewApproved(reviewerID: String, evidenceDigest: String)
        case executionDenied(reason: String)
    }

    enum AuthorizationError: Error, Equatable { case invalidReviewer, invalidEvidence, executionNotAvailable }

    static func approveForReview(reviewerID: String, evidenceDigest: String) throws -> Decision {
        guard !reviewerID.isEmpty, reviewerID.count <= 128 else { throw AuthorizationError.invalidReviewer }
        guard HelperPolicy.isValidHash(evidenceDigest) else { throw AuthorizationError.invalidEvidence }
        return .reviewApproved(reviewerID: reviewerID, evidenceDigest: evidenceDigest)
    }

    static func requireExecutionAuthorization(_ decision: Decision) throws -> Never {
        _ = decision
        throw AuthorizationError.executionNotAvailable
    }
}
