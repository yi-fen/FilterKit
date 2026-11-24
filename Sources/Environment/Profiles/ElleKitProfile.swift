import Foundation

/// Environment-specific contract. Concrete profiles must be backed by verified
/// ElleKit source/version behavior before being advertised as supported.
protocol ElleKitProfile {
    var profileIdentifier: String { get }
    var environmentKind: JailbreakEnvironmentKind { get }
    func resolvePaths() throws -> EnvironmentPaths
    func validatePluginPair(dylibData: Data, plistData: Data) throws
}
