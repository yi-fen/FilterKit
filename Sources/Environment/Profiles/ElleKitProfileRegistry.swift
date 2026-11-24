import Foundation

/// A declarative FilterKit identity profile. Empty binaryFingerprints means the
/// profile is reference-only and can never produce `.matched`.
struct ElleKitProfileRecord: Codable, Equatable {
    struct PackageIdentity: Codable, Equatable {
        var package: String = "ellekit"
        var architectures: [String] = []
        var maintainers: [String] = []
        var origins: [String] = []
        var homepages: [String] = []
    }

    struct BinaryFingerprint: Codable, Equatable {
        let installName: String
        let uuid: String
        let cdHash: String
        var architectures: [String] = []
    }

    let id: String
    let environment: String
    let status: String
    let allowedPackageVersions: [String]
    let packageIdentity: PackageIdentity
    let binaryFingerprints: [BinaryFingerprint]
    let note: String?
}

struct ElleKitProfileDocument: Codable {
    let schemaVersion: Int
    let profiles: [ElleKitProfileRecord]
}

enum ElleKitProfileRegistryError: Error, Equatable {
    case missingBundledResource
    case unsupportedSchema(Int)
    case duplicateIdentifier(String)
}

struct ElleKitProfileRegistry {
    let profiles: [ElleKitProfileRecord]

    init(profiles: [ElleKitProfileRecord]) throws {
        var identifiers = Set<String>()
        for profile in profiles {
            guard identifiers.insert(profile.id).inserted else {
                throw ElleKitProfileRegistryError.duplicateIdentifier(profile.id)
            }
        }
        self.profiles = profiles
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> ElleKitProfileRegistry {
        guard let url = bundle.url(forResource: "ElleKitProfiles", withExtension: "json") else {
            throw ElleKitProfileRegistryError.missingBundledResource
        }
        return try ElleKitProfileRegistry(jsonData: Data(contentsOf: url))
    }

    init(jsonData: Data) throws {
        let document = try JSONDecoder().decode(ElleKitProfileDocument.self, from: jsonData)
        guard document.schemaVersion == 2 else {
            throw ElleKitProfileRegistryError.unsupportedSchema(document.schemaVersion)
        }
        try self.init(profiles: document.profiles)
    }

    /// The shipped RootHide record is deliberately reference-only until exact
    /// binary identity values (including CDHash) are collected from a verified device.
    static var builtIn: ElleKitProfileRegistry {
        let reference = ElleKitProfileRecord(
            id: "roothide-dopamine-ellekit-1.2-3-16e3e7e",
            environment: "rootHide",
            status: "reference-baseline",
            allowedPackageVersions: ["1.2-3"],
            packageIdentity: .init(package: "ellekit", architectures: ["iphoneos-arm64e"],
                                   maintainers: [], origins: [], homepages: []),
            binaryFingerprints: [],
            note: "Reference commit/version only; binary identity is not yet verified."
        )
        return try! ElleKitProfileRegistry(profiles: [reference])
    }
}
