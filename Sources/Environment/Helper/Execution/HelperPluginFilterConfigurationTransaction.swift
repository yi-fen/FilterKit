import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Association-only transaction. It changes Filter.plist and .fk.json, never the dylib.
/// Routed through the authenticated Helper dispatcher; commit remains fail-closed behind its release gate.
/// Startup only inspects this journal. Reconciliation is explicit and is not auto-run at launch.
final class HelperPluginFilterConfigurationTransaction {
    enum Phase: String, Codable { case prepared, staged, backedUp, replacingPlist, replacingManifest, committed }
    enum Failure: Error, Equatable { case notRoot, invalidInput, unsafePath, conflict, hashMismatch, invalidJournal, manualIntervention, io(Int32), injectedCrash(Phase) }
    struct Receipt: Equatable { let transactionID: UUID; let pluginID: UUID; let plistSHA256: String; let manifestSHA256: String; let completedAt: Date }
    enum ActivationEvidenceDisposition: Equatable { case committed, rolledBack, unknown }
    struct ActivationEvidence: Equatable {
        let transactionID: UUID
        let pluginID: UUID
        let disposition: ActivationEvidenceDisposition
        let observedPlistSHA256: String?
        let observedManifestSHA256: String?
        let journalPhase: Phase
    }
    private struct Journal: Codable {
        let schema: Int; let id: UUID; let pluginID: UUID; let plist: String; let manifest: String
        let oldP: String; let oldM: String; let newP: String; let newM: String; var phase: Phase
        var pTmp: String { ".fk-\(id.uuidString.lowercased()).assoc.plist.tmp" }
        var mTmp: String { ".fk-\(id.uuidString.lowercased()).assoc.manifest.tmp" }
        var pBak: String { ".fk-\(id.uuidString.lowercased()).assoc.plist.bak" }
        var mBak: String { ".fk-\(id.uuidString.lowercased()).assoc.manifest.bak" }
        func validate() throws {
            guard schema == 1, HelperPolicy.isSafeLeafName(plist), plist.hasSuffix(".plist"),
                  HelperPolicy.isSafeLeafName(manifest), manifest == String(plist.dropLast(6)) + ".fk.json",
                  [oldP,oldM,newP,newM].allSatisfy(HelperPolicy.isValidHash) else { throw Failure.invalidJournal }
        }
    }
    private let path: String
    private let journalName = ".filterkit-association-two-file.journal"
    private let journalTempName = ".filterkit-association-two-file.journal.tmp"
    private static let lock = NSLock()
    init(directoryPath: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else { throw Failure.unsafePath }
        path = directoryPath
    }

    func execute(_ p: HelperPluginFilterMutationAuthorizer.PreparedMutation, transactionID: UUID = UUID(),
                 simulateCrashAfter: Phase? = nil, retainJournalForOutcomeReconciliation: Bool = false) throws -> Receipt {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard geteuid() == 0 else { throw Failure.notRoot }
        guard p.disposition == .preparedForAtomicCommit else { throw Failure.invalidInput }
        let r = p.request, plist = r.plistFileName, manifest = String(r.dylibFileName.dropLast(6)) + ".fk.json"
        guard HelperPolicy.isSafeLeafName(plist), HelperPolicy.isSafeLeafName(manifest),
              (try? PropertyListSerialization.propertyList(from: p.replacementPlistData, options: [], format: nil)) != nil,
              p.replacementPlistData.count <= 4*1024*1024, p.replacementManifestData.count <= 64*1024,
              SHA256Digest.hex(p.previousPlistData) == r.expectedPlistSHA256.lowercased(),
              SHA256Digest.hex(p.previousManifestData) == r.expectedManifestSHA256.lowercased(),
              SHA256Digest.hex(p.replacementPlistData) == p.response.proposedPlistSHA256,
              SHA256Digest.hex(p.replacementManifestData) == p.response.proposedManifestSHA256,
              p.ownershipProof.pluginID == r.pluginID, p.ownershipProof.dylibFileName == r.dylibFileName,
              p.ownershipProof.plistFileName == plist, p.ownershipProof.plistSHA256 == r.expectedPlistSHA256.lowercased(),
              p.ownershipProof.manifestSHA256 == r.expectedManifestSHA256.lowercased(),
              (p.ownershipProof.manifestSchemaVersion == 3 || p.ownershipProof.manifestSchemaVersion == 4),
              p.ownershipProof.binaryIdentityVerified else { throw Failure.invalidInput }
        let fd = try openDir(); defer { _ = close(fd) }; try validateDir(fd)
        guard try load(fd) == nil else { throw Failure.manualIntervention }
        guard try hash(fd, plist) == r.expectedPlistSHA256.lowercased(), try hash(fd, manifest) == r.expectedManifestSHA256.lowercased(),
              try read(fd, plist, 4*1024*1024) == p.previousPlistData,
              try read(fd, manifest, 64*1024) == p.previousManifestData else { throw Failure.conflict }
        guard transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { throw Failure.invalidInput }
        let id = transactionID
        var j = Journal(schema: 1, id: id, pluginID: r.pluginID, plist: plist, manifest: manifest,
            oldP: r.expectedPlistSHA256.lowercased(), oldM: r.expectedManifestSHA256.lowercased(),
            newP: SHA256Digest.hex(p.replacementPlistData), newM: SHA256Digest.hex(p.replacementManifestData), phase: .prepared)
        for n in [j.pTmp,j.mTmp,j.pBak,j.mBak] { try absent(fd,n) }
        try save(j,fd)
        do {
            try crash(.prepared,simulateCrashAfter)
            try write(p.replacementPlistData,j.pTmp,fd,0o644); try write(p.replacementManifestData,j.mTmp,fd,0o600)
            let stagedManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self, from: read(fd, j.mTmp, 64*1024))
            guard try hash(fd,j.pTmp) == j.newP, try hash(fd,j.mTmp) == j.newM,
                  (try? PropertyListSerialization.propertyList(from: read(fd,j.pTmp,4*1024*1024),options:[],format:nil)) != nil,
                  (stagedManifest?.schemaVersion == p.ownershipProof.manifestSchemaVersion ||
                   (p.ownershipProof.manifestSchemaVersion == 3 && stagedManifest?.schemaVersion == 4)),
                  UUID(uuidString: stagedManifest?.pluginID ?? "") == r.pluginID,
                  stagedManifest?.dylibFileName == r.dylibFileName,
                  stagedManifest?.plistFileName == plist,
                  stagedManifest?.plistSHA256.caseInsensitiveCompare(j.newP) == .orderedSame,
                  Self.hasConsistentBindingMetadata(stagedManifest),
                  Self.filterTargetsMatchBindingMetadata(try read(fd, j.pTmp, 4*1024*1024), stagedManifest) else {
                throw Failure.hashMismatch
            }
            j.phase = .staged; try save(j,fd); try crash(.staged,simulateCrashAfter)
            try copy(fd,plist,j.pBak); try copy(fd,manifest,j.mBak)
            guard try hash(fd,j.pBak) == j.oldP, try hash(fd,j.mBak) == j.oldM, fsync(fd) == 0 else { throw Failure.hashMismatch }
            j.phase = .backedUp; try save(j,fd); try crash(.backedUp,simulateCrashAfter)
            guard try hash(fd,plist) == j.oldP, try hash(fd,manifest) == j.oldM else { throw Failure.conflict }
            j.phase = .replacingPlist; try save(j,fd); try crash(.replacingPlist,simulateCrashAfter)
            try rename(fd,j.pTmp,plist); guard try hash(fd,plist) == j.newP else { throw Failure.hashMismatch }
            j.phase = .replacingManifest; try save(j,fd); try crash(.replacingManifest,simulateCrashAfter)
            try rename(fd,j.mTmp,manifest)
            guard try hash(fd,plist) == j.newP, try hash(fd,manifest) == j.newM, fsync(fd) == 0 else { throw Failure.hashMismatch }
            j.phase = .committed; try save(j,fd); try crash(.committed,simulateCrashAfter)
            if !retainJournalForOutcomeReconciliation { try cleanup(j,fd) }
            return Receipt(transactionID:id,pluginID:r.pluginID,plistSHA256:j.newP,manifestSHA256:j.newM,completedAt:Date())
        } catch let e as Failure {
            if case .injectedCrash = e { throw e }
            if !retainJournalForOutcomeReconciliation { _ = try reconcileLocked(fd) }
            throw e
        } catch {
            if !retainJournalForOutcomeReconciliation { _ = try reconcileLocked(fd) }
            throw Failure.io(errno)
        }
    }

    /// Read-only, transaction-ID-bound evidence probe for APP activation recovery.
    /// It never changes files or clears the journal. Any mismatch remains unknown.
    func inspectActivationEvidence(transactionID: UUID, pluginID: UUID,
                                   oldPlistSHA256: String, oldManifestSHA256: String,
                                   newPlistSHA256: String, newManifestSHA256: String) throws -> ActivationEvidence? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard geteuid() == 0 else { throw Failure.notRoot }
        guard [oldPlistSHA256, oldManifestSHA256, newPlistSHA256, newManifestSHA256].allSatisfy(HelperPolicy.isValidHash),
              transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { throw Failure.invalidInput }
        let fd = try openDir(); defer { _ = close(fd) }; try validateDir(fd)
        guard let j = try load(fd) else { return nil }
        try j.validate()
        guard j.id == transactionID, j.pluginID == pluginID,
              j.oldP == oldPlistSHA256.lowercased(), j.oldM == oldManifestSHA256.lowercased(),
              j.newP == newPlistSHA256.lowercased(), j.newM == newManifestSHA256.lowercased() else {
            return nil
        }
        if try hash(fd, journalTempName) != nil {
            guard let pendingData = try? read(fd, journalTempName, 64*1024),
                  let pending = try? JSONDecoder().decode(Journal.self, from: pendingData),
                  (try? pending.validate()) != nil, pending.id == j.id, pending.pluginID == j.pluginID,
                  pending.oldP == j.oldP, pending.oldM == j.oldM, pending.newP == j.newP, pending.newM == j.newM else {
                return ActivationEvidence(transactionID: j.id, pluginID: j.pluginID, disposition: .unknown,
                    observedPlistSHA256: try hash(fd, j.plist), observedManifestSHA256: try hash(fd, j.manifest), journalPhase: j.phase)
            }
        }
        let currentP = try hash(fd, j.plist), currentM = try hash(fd, j.manifest)
        let backupP = try hash(fd, j.pBak), backupM = try hash(fd, j.mBak)
        let tempP = try hash(fd, j.pTmp), tempM = try hash(fd, j.mTmp)
        let artifactsValid = (backupP == nil || backupP == j.oldP) && (backupM == nil || backupM == j.oldM) &&
            (tempP == nil || tempP == j.newP) && (tempM == nil || tempM == j.newM)
        let disposition: ActivationEvidenceDisposition
        if artifactsValid && j.phase == .committed && currentP == j.newP && currentM == j.newM {
            disposition = .committed
        } else if artifactsValid && j.phase != .committed && currentP == j.oldP && currentM == j.oldM {
            disposition = .rolledBack
        } else {
            disposition = .unknown
        }
        return ActivationEvidence(transactionID: j.id, pluginID: j.pluginID, disposition: disposition,
            observedPlistSHA256: currentP, observedManifestSHA256: currentM, journalPhase: j.phase)
    }

    /// Finalizes only a previously committed journal whose deployed bytes still match it.
    /// Called after the durable activation ledger has recorded Committed.
    func finalizeCommittedActivationJournal(transactionID: UUID, pluginID: UUID,
                                            plistSHA256: String, manifestSHA256: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard geteuid() == 0 else { throw Failure.notRoot }
        let fd = try openDir(); defer { _ = close(fd) }; try validateDir(fd)
        guard let j = try load(fd) else { return }
        try j.validate()
        guard j.id == transactionID, j.pluginID == pluginID, j.phase == .committed,
              try hash(fd, journalTempName) == nil,
              j.newP == plistSHA256.lowercased(), j.newM == manifestSHA256.lowercased(),
              try hash(fd, j.plist) == j.newP, try hash(fd, j.manifest) == j.newM else {
            throw Failure.manualIntervention
        }
        try cleanup(j,fd)
    }

    /// Removes only the journal and artifacts for a transaction whose terminal Ledger
    /// disposition has already been durably persisted. This method never replaces either
    /// deployed file. A mismatch leaves every artifact untouched for manual investigation.
    func finalizeResolvedActivationJournal(transactionID: UUID, pluginID: UUID,
                                           disposition: ActivationEvidenceDisposition,
                                           plistSHA256: String, manifestSHA256: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard geteuid() == 0 else { throw Failure.notRoot }
        guard disposition != .unknown,
              HelperPolicy.isValidHash(plistSHA256), HelperPolicy.isValidHash(manifestSHA256) else {
            throw Failure.invalidInput
        }
        let fd = try openDir(); defer { _ = close(fd) }; try validateDir(fd)
        guard let j = try load(fd) else { return }
        try j.validate()
        guard j.id == transactionID, j.pluginID == pluginID,
              try hash(fd, journalTempName) == nil else { throw Failure.manualIntervention }
        let currentP = try hash(fd, j.plist), currentM = try hash(fd, j.manifest)
        let backupP = try hash(fd, j.pBak), backupM = try hash(fd, j.mBak)
        let tempP = try hash(fd, j.pTmp), tempM = try hash(fd, j.mTmp)
        guard (backupP == nil || backupP == j.oldP), (backupM == nil || backupM == j.oldM),
              (tempP == nil || tempP == j.newP), (tempM == nil || tempM == j.newM) else {
            throw Failure.manualIntervention
        }
        switch disposition {
        case .committed:
            guard j.phase == .committed, j.newP == plistSHA256.lowercased(),
                  j.newM == manifestSHA256.lowercased(), currentP == j.newP, currentM == j.newM else {
                throw Failure.manualIntervention
            }
        case .rolledBack:
            guard j.phase != .committed, j.oldP == plistSHA256.lowercased(),
                  j.oldM == manifestSHA256.lowercased(), currentP == j.oldP, currentM == j.oldM else {
                throw Failure.manualIntervention
            }
        case .unknown:
            throw Failure.invalidInput
        }
        try cleanup(j, fd)
    }

    /// Read-only probe; no automatic startup mutation.
    func inspectPendingJournal() throws -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }; guard geteuid() == 0 else { throw Failure.notRoot }
        let fd = try openDir(); defer { _ = close(fd) }; try validateDir(fd); return try load(fd) != nil
    }
    /// Explicit recovery only. Foreign or missing evidence fails closed.
    func reconcile() throws -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }; guard geteuid() == 0 else { throw Failure.notRoot }
        let fd = try openDir(); defer { _ = close(fd) }; try validateDir(fd); return try reconcileLocked(fd)
    }
    private func reconcileLocked(_ fd:Int32) throws -> Bool {
        guard let j = try load(fd) else { return false }; try j.validate()
        if try hash(fd, journalTempName) != nil {
            guard let pendingData = try? read(fd, journalTempName, 64*1024),
                  let pending = try? JSONDecoder().decode(Journal.self, from: pendingData),
                  (try? pending.validate()) != nil, pending.id == j.id, pending.pluginID == j.pluginID else {
                throw Failure.manualIntervention
            }
        }
        let rows = [(j.plist,j.oldP,j.newP,j.pBak,j.pTmp),(j.manifest,j.oldM,j.newM,j.mBak,j.mTmp)]
        for (dst,old,new,bak,tmp) in rows {
            let c=try hash(fd,dst), b=try hash(fd,bak), t=try hash(fd,tmp)
            if let c,c != old && c != new { throw Failure.manualIntervention }
            if let b,b != old { throw Failure.manualIntervention }; if let t,t != new { throw Failure.manualIntervention }
        }
        if j.phase == .committed {
            guard try hash(fd,j.plist) == j.newP, try hash(fd,j.manifest) == j.newM else { throw Failure.manualIntervention }
        } else {
            for (dst,old,_,bak,_) in rows where try hash(fd,bak) != old {
                guard try hash(fd,dst) == old else { throw Failure.manualIntervention }
            }
            for (dst,old,_,bak,_) in rows where try hash(fd,bak) == old { try rename(fd,bak,dst) }
            guard try hash(fd,j.plist) == j.oldP, try hash(fd,j.manifest) == j.oldM else { throw Failure.manualIntervention }
        }
        try remove(fd,j.pBak,j.oldP); try remove(fd,j.mBak,j.oldM); try remove(fd,j.pTmp,j.newP); try remove(fd,j.mTmp,j.newM)
        if try hash(fd, journalTempName) != nil {
            guard journalTempName.withCString({ unlinkat(fd, $0, 0) }) == 0 else { throw Failure.io(errno) }
        }
        guard fsync(fd) == 0 else { throw Failure.io(errno) }; try clear(fd); return true
    }
    private static func hasConsistentBindingMetadata(_ manifest: FilterKitPluginManifest?) -> Bool {
        guard let manifest else { return false }
        let associations = manifest.softAssociations ?? []
        let associationKeys = HelperBundleIdentifierKey.set(associations.map(\.bundleIdentifier))
        guard associationKeys.count == associations.count,
              associationKeys == HelperBundleIdentifierKey.set(manifest.softAssociatedBundleIdentifiers ?? []),
              !associations.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(manifest.hardBoundBundleIdentifier ?? "") }) else { return false }
        if manifest.schemaVersion == 3 { return manifest.hardBoundBundleIdentifier != nil && manifest.bindingTopology == nil }
        guard manifest.schemaVersion == 4, let topology = manifest.bindingTopology else { return false }
        return topology.schemaVersion == 1 && HelperBundleIdentifierKey.make(topology.fixedOwnerBundleIdentifier ?? "") == HelperBundleIdentifierKey.make(manifest.hardBoundBundleIdentifier ?? "") &&
            topology.additionalAssociations.count == associations.count && topology.additionalAssociations.allSatisfy({ candidate in
                associations.contains { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(candidate.bundleIdentifier) && $0.isEnabled == candidate.isEnabled }
            }) &&
            (topology.fixedOwnerBundleIdentifier != nil || !topology.additionalAssociations.isEmpty)
    }

    private static func filterTargetsMatchBindingMetadata(_ plistData: Data,
                                                           _ manifest: FilterKitPluginManifest?) -> Bool {
        guard let manifest,
              let root = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let filter = root["Filter"] as? [String: Any] else { return false }
        let bundles: [String]
        if let raw = filter["Bundles"] {
            guard let values = raw as? [String] else { return false }
            bundles = values
        } else { bundles = [] }
        let expected: Set<String>
        if manifest.schemaVersion == 3 {
            guard let owner = manifest.hardBoundBundleIdentifier else { return false }
            expected = Set([owner]).union((manifest.softAssociations ?? []).filter(\.isEnabled).map(\.bundleIdentifier))
        } else if manifest.schemaVersion == 4, let topology = manifest.bindingTopology {
            expected = topology.enabledBundleIdentifiers
        } else { return false }
        return HelperBundleIdentifierKey.set(bundles).count == bundles.count && HelperBundleIdentifierKey.set(bundles) == HelperBundleIdentifierKey.set(expected)
    }

    private func openDir() throws -> Int32 {
        var fd=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC); guard fd >= 0 else { throw Failure.unsafePath }
        for c in path.split(separator:"/").map(String.init) { let n=c.withCString{openat(fd,$0,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)}; guard n >= 0 else {_ = close(fd);throw Failure.unsafePath}; _ = close(fd);fd=n }; return fd
    }
    private func validateDir(_ fd:Int32) throws { var s=stat(); guard fstat(fd,&s)==0,(s.st_mode&mode_t(S_IFMT))==mode_t(S_IFDIR),s.st_uid==0,s.st_gid==0,(s.st_mode&0o022)==0 else {throw Failure.unsafePath} }
    private func safeInternalLeaf(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 255 &&
        name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }
    private func read(_ fd:Int32,_ name:String,_ limit:Int) throws -> Data {
        guard safeInternalLeaf(name) else {throw Failure.invalidInput}; let f=name.withCString{openat(fd,$0,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)}; guard f>=0 else {throw Failure.unsafePath}; defer{_ = close(f)}
        var s=stat();guard fstat(f,&s)==0,(s.st_mode&mode_t(S_IFMT))==mode_t(S_IFREG),s.st_uid==0,s.st_gid==0,s.st_size>=0,s.st_size<=limit else{throw Failure.unsafePath}
        var d=Data(),b=[UInt8](repeating:0,count:32768);while true{let n=DarwinOrGlibcRead(f,&b,b.count);if n<0 && errno==EINTR{continue};guard n>=0 else{throw Failure.io(errno)};if n==0{break};d.append(contentsOf:b.prefix(n));guard d.count<=limit else{throw Failure.unsafePath}};return d
    }
    private func hash(_ fd:Int32,_ name:String) throws -> String? {
        guard safeInternalLeaf(name) else { throw Failure.invalidInput }
        let f = name.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        if f < 0 { if errno == ENOENT { return nil }; throw Failure.unsafePath }
        defer { _ = close(f) }
        var st = stat()
        guard fstat(f, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              st.st_uid == 0, st.st_gid == 0, st.st_size >= 0, st.st_size <= 4 * 1024 * 1024 else { throw Failure.unsafePath }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 32 * 1024)
        while true {
            let count = DarwinOrGlibcRead(f, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure.io(errno) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return SHA256Digest.hex(data)
    }
    private func write(_ d:Data,_ name:String,_ fd:Int32,_ mode:mode_t) throws {
        let f=name.withCString{openat(fd,$0,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,mode)};guard f>=0 else{throw Failure.io(errno)};defer{_ = close(f)}
        guard fchown(f,0,0)==0,fchmod(f,mode)==0 else{throw Failure.io(errno)}
        try d.withUnsafeBytes{raw in var o=0;while o<raw.count{let n=DarwinOrGlibcWrite(f,raw.baseAddress!.advanced(by:o),raw.count-o);if n<0 && errno==EINTR{continue};guard n>0 else{throw Failure.io(errno)};o+=n}}
        guard fsync(f)==0 else{throw Failure.io(errno)}
    }
    private func copy(_ fd:Int32,_ src:String,_ dst:String) throws { try write(read(fd,src,4*1024*1024),dst,fd,0o600) }
    private func rename(_ fd:Int32,_ src:String,_ dst:String) throws { guard safeInternalLeaf(src),safeInternalLeaf(dst) else{throw Failure.invalidInput};let x=src.withCString{a in dst.withCString{b in renameat(fd,a,fd,b)}};guard x==0,fsync(fd)==0 else{throw Failure.io(errno)} }
    private func absent(_ fd:Int32,_ n:String) throws {guard try hash(fd,n)==nil else{throw Failure.conflict}}
    private func save(_ j:Journal,_ fd:Int32) throws {let tmp=journalTempName;try absent(fd,tmp);try write(try JSONEncoder().encode(j),tmp,fd,0o600);let x=tmp.withCString{a in journalName.withCString{b in renameat(fd,a,fd,b)}};guard x==0,fsync(fd)==0 else{throw Failure.io(errno)}}
    private func load(_ fd:Int32) throws -> Journal? {if try hash(fd,journalName)==nil { if try hash(fd,journalTempName) != nil { throw Failure.invalidJournal }; return nil };guard let j=try? JSONDecoder().decode(Journal.self,from:read(fd,journalName,64*1024)) else{throw Failure.invalidJournal};try j.validate();return j}
    private func clear(_ fd:Int32) throws {guard journalName.withCString({unlinkat(fd,$0,0)})==0 || errno==ENOENT else{throw Failure.io(errno)}}
    private func remove(_ fd:Int32,_ n:String,_ expected:String) throws {if try hash(fd,n)==expected{guard n.withCString({unlinkat(fd,$0,0)})==0 else{throw Failure.io(errno)}}else if try hash(fd,n) != nil{throw Failure.manualIntervention}}
    private func cleanup(_ j:Journal,_ fd:Int32) throws {try remove(fd,j.pBak,j.oldP);try remove(fd,j.mBak,j.oldM);try remove(fd,j.pTmp,j.newP);try remove(fd,j.mTmp,j.newM);guard fsync(fd)==0 else{throw Failure.io(errno)};try clear(fd)}
    private func crash(_ p:Phase,_ requested:Phase?) throws {if p==requested{throw Failure.injectedCrash(p)}}
}

#if canImport(Darwin)
private func DarwinOrGlibcRead(_ fd:Int32,_ buffer:UnsafeMutableRawPointer,_ count:Int)->Int { Darwin.read(fd,buffer,count) }
private func DarwinOrGlibcWrite(_ fd:Int32,_ buffer:UnsafeRawPointer,_ count:Int)->Int { Darwin.write(fd,buffer,count) }
#else
private func DarwinOrGlibcRead(_ fd:Int32,_ buffer:UnsafeMutableRawPointer,_ count:Int)->Int { Glibc.read(fd,buffer,count) }
private func DarwinOrGlibcWrite(_ fd:Int32,_ buffer:UnsafeRawPointer,_ count:Int)->Int { Glibc.write(fd,buffer,count) }
#endif
