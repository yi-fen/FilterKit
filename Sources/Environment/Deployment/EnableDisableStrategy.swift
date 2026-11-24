import Foundation

enum EnableDisableStrategy: String, Codable, Equatable {
    /// No file mutation strategy is enabled until its exact injector behavior is verified.
    case unverified
    case verifiedProfileStrategy
}

enum EnableDisableProbeStatus: String, Codable, Equatable {
    case verified
    case referenceOnly
    case unsupported
    case evidenceMissing
}

struct EnableDisableProfileEvidence: Codable, Equatable {
    let profileIdentifier: String
    let environment: JailbreakEnvironmentKind
    let elleKitVersion: String?
    let sourceCommit: String?
    let sourceRevisionVerified: Bool
    let disableMechanismVerified: Bool
    let enableMechanismVerified: Bool
    let preservesOriginalPlistSemantics: Bool
    let deviceValidated: Bool

    var status: EnableDisableProbeStatus {
        guard sourceRevisionVerified, disableMechanismVerified,
              enableMechanismVerified, preservesOriginalPlistSemantics else {
            return .referenceOnly
        }
        guard deviceValidated else { return .evidenceMissing }
        return .verified
    }
}

struct EnableDisableStrategyResolution: Equatable {
    let strategy: EnableDisableStrategy
    let status: EnableDisableProbeStatus
    let reasonKey: String
    let profileIdentifier: String?

    var permitsMutation: Bool { strategy == .verifiedProfileStrategy && status == .verified }
}

struct EnableDisableStrategyResolver {
    func resolve(environment: JailbreakEnvironmentKind,
                 evidence: EnableDisableProfileEvidence?) -> EnableDisableStrategyResolution {
        guard environment == .rootHide || environment == .rootless else {
            return .init(strategy: .unverified, status: .unsupported,
                         reasonKey: "deployment.strategy.unsupported_environment", profileIdentifier: nil)
        }
        guard let evidence else {
            return .init(strategy: .unverified, status: .evidenceMissing,
                         reasonKey: "deployment.strategy.no_profile_evidence", profileIdentifier: nil)
        }
        guard evidence.environment == environment else {
            return .init(strategy: .unverified, status: .unsupported,
                         reasonKey: "deployment.strategy.environment_mismatch", profileIdentifier: evidence.profileIdentifier)
        }
        guard evidence.status == .verified else {
            return .init(strategy: .unverified, status: evidence.status,
                         reasonKey: "deployment.strategy.not_verified", profileIdentifier: evidence.profileIdentifier)
        }
        return .init(strategy: .verifiedProfileStrategy, status: .verified,
                     reasonKey: "deployment.strategy.verified", profileIdentifier: evidence.profileIdentifier)
    }
}
