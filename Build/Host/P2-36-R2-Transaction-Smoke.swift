import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

struct Fixture {
    let directory: URL
    let pluginID: UUID
    let plistName: String
    let manifestName: String
    let oldPlist: Data
    let newPlist: Data
    let oldManifest: Data
    let newManifest: Data
    let prepared: HelperPluginFilterMutationAuthorizer.PreparedMutation
    let transaction: HelperPluginFilterConfigurationTransaction
}

func makeFixture() throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("fk-r2-smoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    let pluginID = UUID(), dylib = "Example.dylib", plistName = "Example.plist", manifestName = "Example.fk.json"
    let plist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.host"]]], format: .xml, options: 0)
    let plistHash = SHA256Digest.hex(plist), dylibHash = String(repeating: "c", count: 64)
    func manifest(_ associations: [FilterKitManifestSoftAssociation]) throws -> Data {
        let value = FilterKitPluginManifest(schemaVersion: 3, pluginID: pluginID.uuidString,
            dylibFileName: dylib, plistFileName: plistName, dylibSHA256: dylibHash,
            plistSHA256: plistHash, hardBoundBundleIdentifier: "com.example.host",
            softAssociatedBundleIdentifiers: associations.map(\.bundleIdentifier),
            machOIdentitySHA256: String(repeating: "d", count: 64), softAssociations: associations)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    let oldManifest = try manifest([FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: false)])
    let newManifest = try manifest([
        FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: false),
        FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.beta", isEnabled: false)
    ])
    try plist.write(to: directory.appendingPathComponent(plistName))
    try oldManifest.write(to: directory.appendingPathComponent(manifestName))
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: directory.appendingPathComponent(plistName).path)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent(manifestName).path)
    let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: pluginID,
        action: .replaceSoftAssociations, dylibFileName: dylib, plistFileName: plistName,
        targetBundleIdentifier: "com.example.host", expectedPlistSHA256: plistHash,
        expectedManifestSHA256: SHA256Digest.hex(oldManifest), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        desiredSoftAssociations: [
            HelperPluginSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: false),
            HelperPluginSoftAssociation(bundleIdentifier: "com.example.beta", isEnabled: false)
        ])
    let proof = try HelperOwnershipProof(pluginID: pluginID, dylibFileName: dylib, plistFileName: plistName,
        dylibSHA256: dylibHash, plistSHA256: plistHash, manifestSchemaVersion: 3,
        manifestSHA256: SHA256Digest.hex(oldManifest), binaryIdentityVerified: true)
    let prepared = HelperPluginFilterMutationAuthorizer.PreparedMutation(request: request,
        ownershipProof: proof, previousPlistData: plist, replacementPlistData: plist,
        previousManifestData: oldManifest, replacementManifestData: newManifest,
        disposition: .preparedForAtomicCommit)
    return Fixture(directory: directory, pluginID: pluginID, plistName: plistName,
        manifestName: manifestName, oldPlist: plist, newPlist: plist,
        oldManifest: oldManifest, newManifest: newManifest, prepared: prepared,
        transaction: try HelperPluginFilterConfigurationTransaction(directoryPath: directory.path))
}

func runCrashWorker(directoryPath: String, pluginID: UUID, phase: HelperPluginFilterConfigurationTransaction.Phase) throws -> Never {
    let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
    let plistName = "Example.plist", manifestName = "Example.fk.json", dylibName = "Example.dylib"
    let plist = try Data(contentsOf: directory.appendingPathComponent(plistName))
    let oldManifest = try Data(contentsOf: directory.appendingPathComponent(manifestName))
    let newManifestData = try Data(contentsOf: directory.appendingPathComponent(".new-manifest-fixture"))
    let currentManifest = try JSONDecoder().decode(FilterKitPluginManifest.self, from: oldManifest)
    let proposedManifest = try JSONDecoder().decode(FilterKitPluginManifest.self, from: newManifestData)
    let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: pluginID,
        action: .replaceSoftAssociations, dylibFileName: dylibName, plistFileName: plistName,
        targetBundleIdentifier: currentManifest.hardBoundBundleIdentifier!,
        expectedPlistSHA256: SHA256Digest.hex(plist), expectedManifestSHA256: SHA256Digest.hex(oldManifest),
        createdAt: Date(), desiredSoftAssociations: (proposedManifest.softAssociations ?? []).map {
            HelperPluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled)
        })
    let proof = try HelperOwnershipProof(pluginID: pluginID, dylibFileName: dylibName, plistFileName: plistName,
        dylibSHA256: currentManifest.dylibSHA256, plistSHA256: SHA256Digest.hex(plist),
        manifestSchemaVersion: currentManifest.schemaVersion, manifestSHA256: SHA256Digest.hex(oldManifest),
        binaryIdentityVerified: true)
    let prepared = HelperPluginFilterMutationAuthorizer.PreparedMutation(request: request,
        ownershipProof: proof, previousPlistData: plist, replacementPlistData: plist,
        previousManifestData: oldManifest, replacementManifestData: newManifestData,
        disposition: .preparedForAtomicCommit)
    let transaction = try HelperPluginFilterConfigurationTransaction(directoryPath: directoryPath)
    do {
        _ = try transaction.execute(prepared, simulateCrashAfter: phase)
        exit(91)
    } catch HelperPluginFilterConfigurationTransaction.Failure.injectedCrash {
        // Simulate an actual process death after the durable journal phase boundary.
        _ = kill(getpid(), SIGKILL)
        exit(92)
    }
}

@main
struct P236R2TransactionSmoke {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 5, args[1] == "--crash-worker",
           let pluginID = UUID(uuidString: args[3]),
           let phase = HelperPluginFilterConfigurationTransaction.Phase(rawValue: args[4]) {
            try runCrashWorker(directoryPath: args[2], pluginID: pluginID, phase: phase)
        }
        guard geteuid() == 0 else { fputs("SKIP: root required for ownership transaction tests\n", stderr); exit(2) }
        let phases: [HelperPluginFilterConfigurationTransaction.Phase] = [
            .prepared, .staged, .backedUp, .replacingPlist, .replacingManifest, .committed
        ]
        for phase in phases {
            let f = try makeFixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            do { _ = try f.transaction.execute(f.prepared, simulateCrashAfter: phase); fatalError("expected injected crash") }
            catch let error as HelperPluginFilterConfigurationTransaction.Failure {
                expect(error == .injectedCrash(phase), "injected crash phase \(phase)")
            }
            let journalVisible = try f.transaction.inspectPendingJournal()
            expect(journalVisible, "journal visible after \(phase)")
            let didReconcile = try f.transaction.reconcile()
            expect(didReconcile, "reconcile after \(phase)")
            let plist = try Data(contentsOf: f.directory.appendingPathComponent(f.plistName))
            let manifest = try Data(contentsOf: f.directory.appendingPathComponent(f.manifestName))
            if phase == .committed {
                expect(plist == f.newPlist && manifest == f.newManifest, "committed state retained")
            } else {
                expect(plist == f.oldPlist && manifest == f.oldManifest, "rollback after \(phase)")
            }
            let journalCleared = try f.transaction.inspectPendingJournal()
            expect(!journalCleared, "journal cleared after \(phase)")
            print("PASS Journal phase recovery: \(phase)")
        }
        do {
            let f = try makeFixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            let receipt = try f.transaction.execute(f.prepared)
            expect(receipt.pluginID == f.pluginID, "receipt plugin binding")
            let committedPlist = try Data(contentsOf: f.directory.appendingPathComponent(f.plistName))
            let committedManifest = try Data(contentsOf: f.directory.appendingPathComponent(f.manifestName))
            expect(committedPlist == f.oldPlist, "Filter.plist byte preservation")
            expect(committedManifest == f.newManifest, "manifest commit")
            print("PASS Successful two-file commit and Filter.plist byte preservation")
        }
        do {
            let f = try makeFixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            do { _ = try f.transaction.execute(f.prepared, simulateCrashAfter: .replacingManifest); fatalError("expected injected crash") }
            catch HelperPluginFilterConfigurationTransaction.Failure.injectedCrash { }
            let foreign = Data("foreign".utf8)
            try foreign.write(to: f.directory.appendingPathComponent(f.plistName))
            do { _ = try f.transaction.reconcile(); fatalError("expected fail-closed recovery") }
            catch HelperPluginFilterConfigurationTransaction.Failure.manualIntervention { }
            let preservedForeign = try Data(contentsOf: f.directory.appendingPathComponent(f.plistName))
            expect(preservedForeign == foreign, "foreign bytes preserved")
            print("PASS Foreign modification fails closed")
        }
        do {
            let f = try makeFixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
            try f.newManifest.write(to: f.directory.appendingPathComponent(".new-manifest-fixture"))
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--crash-worker", f.directory.path, f.pluginID.uuidString, "replacingManifest"]
            try child.run(); child.waitUntilExit()
            expect(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL,
                   "child process must be killed after durable journal boundary")
            let childJournalVisible = try f.transaction.inspectPendingJournal()
            expect(childJournalVisible, "parent sees child journal after process death")
            let parentRecovered = try f.transaction.reconcile()
            expect(parentRecovered, "parent recovers after process death")
            let recoveredPlist = try Data(contentsOf: f.directory.appendingPathComponent(f.plistName))
            let recoveredManifest = try Data(contentsOf: f.directory.appendingPathComponent(f.manifestName))
            expect(recoveredPlist == f.oldPlist && recoveredManifest == f.oldManifest,
                   "cross-process recovery restores both original files")
            print("PASS SIGKILL process-death recovery after first file replacement")
        }
        do {
            let req = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(), action: .replaceSoftAssociations,
                dylibFileName: "Example.dylib", plistFileName: "Example.plist", targetBundleIdentifier: "com.example.host",
                expectedPlistSHA256: String(repeating: "a", count: 64), expectedManifestSHA256: String(repeating: "b", count: 64),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                desiredSoftAssociations: [HelperPluginSoftAssociation(bundleIdentifier: "com.example.alpha", isEnabled: false)])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let envelope = HelperIPCEnvelope(messageType: .pluginFilterMutationCommitRequest, requestID: req.requestID,
                createdAt: req.createdAt, nonce: "0123456789abcdef0123456789abcdef", payload: try encoder.encode(req))
            let codec = HelperIPCFrameCodec(); let frame = try codec.encode(envelope); let decoded = try codec.decode(frame)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let decodedRequest = try decoder.decode(HelperPluginFilterMutationRequest.self, from: decoded.payload!)
            expect(decodedRequest == req, "association request IPC round trip")
            let legacyRequest = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(), action: .enableForApp,
                dylibFileName: "Example.dylib", plistFileName: "Example.plist", targetBundleIdentifier: "com.example.alpha",
                expectedPlistSHA256: String(repeating: "a", count: 64), expectedManifestSHA256: String(repeating: "b", count: 64),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000))
            let legacyEncoded = try encoder.encode(legacyRequest)
            var legacyObject = try JSONSerialization.jsonObject(with: legacyEncoded) as! [String: Any]
            legacyObject.removeValue(forKey: "desiredSoftAssociations")
            let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
            let decodedLegacy = try decoder.decode(HelperPluginFilterMutationRequest.self, from: legacyData)
            expect(decodedLegacy.action == .enableForApp && decodedLegacy.desiredSoftAssociations == nil,
                   "legacy per-App request remains decodable")
            var malformed = frame; malformed.append(0)
            do { _ = try codec.decode(malformed); fatalError("trailing frame bytes accepted") }
            catch HelperIPCCodecError.truncatedFrame { }
            print("PASS IPC envelope, full association request, and legacy request compatibility")
        }
        expect(HelperRequestDispatcher.pluginAssociationCommitReleased == false, "Helper Release Gate remains closed")
        expect(HelperDeploymentCoordinator.pluginAssociationCommitReleased == false, "App Release Gate remains closed")
        print("PASS Both production Release Gates remain closed")
        print("P2-36-R2 Phase 2 transaction smoke: PASS")
    }
}
