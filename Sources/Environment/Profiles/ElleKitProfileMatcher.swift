import Foundation

enum ElleKitProfileMatch: String, Codable, Equatable {
    case matched
    case versionMismatch
    case identityMismatch
    case unknownFingerprint
    case unverifiable
    case ambiguous
    case notEvaluated
    case environmentNotSupported
}

struct ElleKitProfileMatchResult: Equatable {
    let outcome: ElleKitProfileMatch
    let profileIdentifier: String?
    let reason: String
}

struct ElleKitProfileMatcher {
    private let registry: ElleKitProfileRegistry

    init(registry: ElleKitProfileRegistry = .builtIn) {
        self.registry = registry
    }

    func match(environment: JailbreakEnvironmentKind,
               package: ElleKitPackageMetadata?,
               fingerprints: [ElleKitBinaryFingerprint],
               hasInaccessibleEvidence: Bool = false) -> ElleKitProfileMatchResult {
        guard environment == .rootHide || environment == .rootless else {
            return result(.environmentNotSupported, nil, "environment_not_supported")
        }
        let environmentProfiles = registry.profiles.filter {
            normalizedEnvironment($0.environment) == environment
        }
        guard !environmentProfiles.isEmpty else {
            return result(.unknownFingerprint, nil, "no_profile_for_environment")
        }
        guard let package = package, package.status == "install ok installed" else {
            return result(hasInaccessibleEvidence ? .unverifiable : .unverifiable,
                          nil, "installed_package_metadata_unavailable")
        }

        let packageProfiles = environmentProfiles.filter { $0.packageIdentity.package == package.package }
        guard !packageProfiles.isEmpty else {
            return result(.identityMismatch, nil, "package_identity_mismatch")
        }

        var identityCompatible: [ElleKitProfileRecord] = []
        var packageIdentityIncomplete = false
        for profile in packageProfiles {
            let identity = profile.packageIdentity
            if !identity.architectures.isEmpty {
                guard let architecture = package.architecture else {
                    packageIdentityIncomplete = true
                    continue
                }
                if !identity.architectures.contains(architecture) { continue }
            }
            if !identity.maintainers.isEmpty {
                guard let maintainer = package.maintainer else {
                    packageIdentityIncomplete = true
                    continue
                }
                if !identity.maintainers.contains(maintainer) { continue }
            }
            if !identity.origins.isEmpty {
                guard let origin = package.origin else {
                    packageIdentityIncomplete = true
                    continue
                }
                if !identity.origins.contains(origin) { continue }
            }
            if !identity.homepages.isEmpty {
                guard let homepage = package.homepage else {
                    packageIdentityIncomplete = true
                    continue
                }
                if !identity.homepages.contains(homepage) { continue }
            }
            identityCompatible.append(profile)
        }
        guard !identityCompatible.isEmpty else {
            if packageIdentityIncomplete {
                return result(.unverifiable, packageProfiles.first?.id, "package_identity_fields_unavailable")
            }
            return result(.identityMismatch, packageProfiles.first?.id, "package_identity_fields_conflict")
        }

        let versionProfiles = identityCompatible.filter {
            $0.allowedPackageVersions.isEmpty || package.version.map($0.allowedPackageVersions.contains) == true
        }
        guard !versionProfiles.isEmpty else {
            return result(.versionMismatch, identityCompatible.first?.id, "package_version_outside_profile")
        }

        // A package/version match is not a binary identity match. Profiles without
        // pinned installName + UUID + CDHash remain explicitly unknown.
        let profilesWithBinaryPins = versionProfiles.filter {
            $0.status == "verified" && !$0.binaryFingerprints.isEmpty
        }
        guard !profilesWithBinaryPins.isEmpty else {
            return result(.unknownFingerprint, versionProfiles.first?.id, "profile_has_no_verified_binary_fingerprint")
        }
        guard !fingerprints.isEmpty else {
            return result(hasInaccessibleEvidence ? .unverifiable : .unverifiable,
                          profilesWithBinaryPins.first?.id, "binary_fingerprint_unavailable")
        }

        var sawIncompleteActual = false
        var matchingProfileIDs = Set<String>()
        var conflictingCompleteFingerprint = false
        for profile in profilesWithBinaryPins {
            var profileMatched = false
            for expected in profile.binaryFingerprints {
                for actual in fingerprints {
                    guard let actualInstallName = actual.installName,
                          let actualUUID = actual.uuid,
                          let actualCDHash = actual.cdHash else {
                        sawIncompleteActual = true
                        continue
                    }
                    let identityMatches = actualInstallName == expected.installName &&
                        normalizeUUID(actualUUID) == normalizeUUID(expected.uuid) &&
                        normalizeHash(actualCDHash) == normalizeHash(expected.cdHash)
                    guard identityMatches else {
                        conflictingCompleteFingerprint = true
                        continue
                    }
                    if !expected.architectures.isEmpty {
                        guard let architecture = actual.architecture else {
                            sawIncompleteActual = true
                            continue
                        }
                        if !expected.architectures.contains(architecture) { continue }
                    }
                    profileMatched = true
                }
            }
            if profileMatched { matchingProfileIDs.insert(profile.id) }
        }

        // Never choose the first record when duplicate or overlapping Profile
        // definitions both claim the same observed binary identity.
        if matchingProfileIDs.count > 1 {
            return result(.ambiguous, nil, "multiple_profiles_match_same_evidence")
        }
        if let matchedID = matchingProfileIDs.first {
            if conflictingCompleteFingerprint {
                return result(.ambiguous, matchedID, "matching_and_conflicting_binary_candidates")
            }
            return result(.matched, matchedID, "package_and_binary_identity_matched")
        }
        if sawIncompleteActual {
            return result(.unverifiable, profilesWithBinaryPins.first?.id, "required_binary_fingerprint_fields_missing")
        }
        return result(.identityMismatch, profilesWithBinaryPins.first?.id, "binary_fingerprint_conflict")
    }

    private func normalizedEnvironment(_ value: String) -> JailbreakEnvironmentKind? {
        switch value.lowercased() {
        case "roothide": return .rootHide
        case "rootless": return .rootless
        default: return nil
        }
    }

    private func matchesAny(_ value: String?, allowed: [String]) -> Bool {
        guard let value = value else { return false }
        return allowed.contains(value)
    }

    private func normalizeUUID(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private func normalizeHash(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private func result(_ outcome: ElleKitProfileMatch, _ identifier: String?, _ reason: String) -> ElleKitProfileMatchResult {
        ElleKitProfileMatchResult(outcome: outcome, profileIdentifier: identifier, reason: reason)
    }
}
