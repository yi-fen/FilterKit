import Foundation

/// P1-26 request-level preflight. It selects one authorization route for an entire paired
/// dylib/plist operation. It deliberately creates no ownership proof and performs no writes.
struct HelperDeploymentRouteResolver {
    enum Route: Equatable { case firstInstall, update }
    enum OwnershipEvidence: Equatable { case verifiedUnowned, filterKitOwned, packageManagerOwned, unknown }
    enum ResolutionError: Error, Equatable {
        case invalidPair, mixedPluginIDs, duplicateRequestIDs, filenamePairMismatch
        case manifestOwnershipMismatch, packageManagerOwned, ownershipUnknown
    }

    func resolve(requests: [HelperOperationRequest], manifestExists: Bool,
                 ownership: OwnershipEvidence) throws -> Route {
        guard requests.count == 2 else { throw ResolutionError.invalidPair }
        guard Set(requests.map(\.pluginID)).count == 1 else { throw ResolutionError.mixedPluginIDs }
        guard Set(requests.map(\.requestID)).count == 2 else { throw ResolutionError.duplicateRequestIDs }
        guard let dylib = requests.first(where: { $0.operation == .installDylib }),
              let plist = requests.first(where: { $0.operation == .replaceFilterPlist }),
              requests.allSatisfy({ $0.stagingRelativePath.map(HelperPolicy.isSafeRelativePath) == true &&
                  $0.expectedSHA256.map(HelperPolicy.isValidHash) == true && HelperPolicy.isSafeLeafName($0.targetFileName) }),
              dylib.targetFileName.lowercased().hasSuffix(".dylib"),
              plist.targetFileName.lowercased().hasSuffix(".plist"),
              String(dylib.targetFileName.dropLast(6)).lowercased() == String(plist.targetFileName.dropLast(6)).lowercased() else {
            throw ResolutionError.filenamePairMismatch
        }
        if manifestExists {
            switch ownership {
            case .filterKitOwned: return .update
            case .packageManagerOwned: throw ResolutionError.packageManagerOwned
            case .unknown, .verifiedUnowned: throw ResolutionError.manifestOwnershipMismatch
            }
        }
        switch ownership {
        case .verifiedUnowned: return .firstInstall
        case .packageManagerOwned: throw ResolutionError.packageManagerOwned
        case .filterKitOwned: throw ResolutionError.manifestOwnershipMismatch
        case .unknown: throw ResolutionError.ownershipUnknown
        }
    }
}

/// A narrow orchestration boundary used by the future runtime dispatcher. Implementations must
/// obtain root-side evidence themselves; callers cannot pass an ownership proof through IPC.
protocol HelperDeploymentRouteExecuting {
    func preflightFirstInstall(_ requests: [HelperOperationRequest],
                               context: HelperAuthenticatedPeerContext) throws -> String
    func preflightUpdate(_ requests: [HelperOperationRequest],
                         context: HelperAuthenticatedPeerContext) throws -> String
}

/// Pairs the two legacy operation records into one indivisible deployment unit. This avoids
/// dispatching a dylib write independently from its matching Filter.plist update.
struct HelperDeploymentBatchValidator {
    func validate(_ requests: [HelperOperationRequest]) throws -> (pluginID: UUID, dylib: HelperOperationRequest, plist: HelperOperationRequest) {
        guard requests.count == 2,
              Set(requests.map(\.requestID)).count == 2,
              Set(requests.map(\.pluginID)).count == 1,
              let dylib = requests.first(where: { $0.operation == .installDylib }),
              let plist = requests.first(where: { $0.operation == .replaceFilterPlist }),
              dylib.pluginID == plist.pluginID,
              dylib.targetFileName.lowercased().hasSuffix(".dylib"),
              plist.targetFileName.lowercased().hasSuffix(".plist"),
              String(dylib.targetFileName.dropLast(6)).lowercased() == String(plist.targetFileName.dropLast(6)).lowercased(),
              [dylib, plist].allSatisfy({
                  HelperPolicy.isSafeLeafName($0.targetFileName) &&
                  $0.stagingRelativePath.map(HelperPolicy.isSafeRelativePath) == true &&
                  $0.expectedSHA256.map(HelperPolicy.isValidHash) == true
              }) else { throw HelperDeploymentRouteResolver.ResolutionError.invalidPair }
        return (dylib.pluginID, dylib, plist)
    }
}
