import Foundation

func require126(_ condition: Bool, _ message: String) throws {
    guard condition else { throw NSError(domain: "P1-26", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main struct P126RoutingSmoke {
    static func main() throws {
        let pluginID = UUID(), now = Date()
        let pair = [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Test.dylib", targetFileName: "Test.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: now),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Test.plist", targetFileName: "Test.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: now)
        ]
        let validator = HelperDeploymentBatchValidator()
        let validated = try validator.validate(pair)
        try require126(validated.pluginID == pluginID, "valid pair rejected")
        let firstRoute = try HelperDeploymentRouteResolver().resolve(requests: pair, manifestExists: false, ownership: .verifiedUnowned)
        try require126(firstRoute == .firstInstall, "first-install route mismatch")
        let updateRoute = try HelperDeploymentRouteResolver().resolve(requests: pair, manifestExists: true, ownership: .filterKitOwned)
        try require126(updateRoute == .update, "update route mismatch")
        do {
            _ = try HelperDeploymentRouteResolver().resolve(requests: pair, manifestExists: true, ownership: .packageManagerOwned)
            throw NSError(domain: "P1-26", code: 2, userInfo: [NSLocalizedDescriptionKey: "package-manager ownership accepted"])
        } catch HelperDeploymentRouteResolver.ResolutionError.packageManagerOwned { }
        do {
            _ = try validator.validate(Array(pair.prefix(1)))
            throw NSError(domain: "P1-26", code: 3, userInfo: [NSLocalizedDescriptionKey: "partial deployment accepted"])
        } catch HelperDeploymentRouteResolver.ResolutionError.invalidPair { }
        print("P1-26 routing smoke: PASS (atomic pair, first-install/update split, package-manager rejection, partial-pair rejection)")
    }
}
