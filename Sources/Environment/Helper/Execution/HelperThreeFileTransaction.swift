import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Crash-consistent transaction for the deployed dylib, matching Filter.plist and Root-owned
/// FilterKit manifest. This primitive is intentionally not registered with HelperRuntime.
final class HelperThreeFileTransactionExecutor {
    enum Route: Equatable { case firstInstall, update }
    enum Phase: String, Codable, CaseIterable {
        case prepared, backingUp, installingDylib, installingPlist, installingManifest, committed
    }
    enum TransactionError: Error, Equatable {
        case notRoot, invalidInput, unsafeDirectory, unsafeFile, conflict, hashMismatch
        case io(Int32), journalInvalid, manualIntervention, injectedCrash(Phase)
    }
    struct Receipt: Equatable {
        let transactionID: UUID
        let pluginID: UUID
        let route: String
        let dylibSHA256: String
        let plistSHA256: String
        let manifestSHA256: String
        let completedAt: Date
    }
    private struct Journal: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        let pluginID: UUID
        let dylibName: String
        let plistName: String
        let manifestName: String
        let newDylibHash: String
        let newPlistHash: String
        let newManifestHash: String
        let oldDylibHash: String?
        let oldPlistHash: String?
        let oldManifestHash: String?
        var phase: Phase
        var tempDylib: String { ".fk-\(transactionID.uuidString.lowercased()).dylib.tmp" }
        var tempPlist: String { ".fk-\(transactionID.uuidString.lowercased()).plist.tmp" }
        var tempManifest: String { ".fk-\(transactionID.uuidString.lowercased()).manifest.tmp" }
        var backupDylib: String { ".fk-\(transactionID.uuidString.lowercased()).dylib.bak" }
        var backupPlist: String { ".fk-\(transactionID.uuidString.lowercased()).plist.bak" }
        var backupManifest: String { ".fk-\(transactionID.uuidString.lowercased()).manifest.bak" }
        func validate() throws {
            guard schemaVersion == 1, HelperPolicy.isSafeLeafName(dylibName), dylibName.lowercased().hasSuffix(".dylib"),
                  HelperPolicy.isSafeLeafName(plistName), plistName.lowercased().hasSuffix(".plist"),
                  String(dylibName.dropLast(6)).lowercased() == String(plistName.dropLast(6)).lowercased(),
                  manifestName == String(dylibName.dropLast(6)) + ".fk.json",
                  [newDylibHash, newPlistHash, newManifestHash].allSatisfy(HelperPolicy.isValidHash),
                  [oldDylibHash, oldPlistHash, oldManifestHash].compactMap({ $0 }).allSatisfy(HelperPolicy.isValidHash),
                  (oldDylibHash == nil) == (oldPlistHash == nil),
                  (oldDylibHash == nil) == (oldManifestHash == nil) else { throw TransactionError.journalInvalid }
        }
    }

    private let directoryPath: String
    private static let processLock = NSLock()
    private let journalLeaf = ".filterkit-three-file.journal"
    init(directoryPath: String) throws {
        guard HelperPolicy.isAbsoluteCleanPath(directoryPath), directoryPath != "/" else { throw TransactionError.unsafeDirectory }
        self.directoryPath = directoryPath
    }

    func execute(pluginID: UUID, dylibName: String, plistName: String, dylib: Data, plist: Data,
                 manifest: Data, route: Route, expectedPrevious: (dylib: String, plist: String, manifest: String)? = nil,
                 simulateCrashAfter: Phase? = nil) throws -> Receipt {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        guard HelperPolicy.isSafeLeafName(dylibName), dylibName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistName), plistName.lowercased().hasSuffix(".plist"),
              String(dylibName.dropLast(6)).lowercased() == String(plistName.dropLast(6)).lowercased(),
              (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) != nil,
              dylib.count <= 64 * 1024 * 1024, plist.count <= 64 * 1024 * 1024,
              manifest.count <= 256 * 1024 else { throw TransactionError.invalidInput }
        guard let manifestObject = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              (manifestObject["schemaVersion"] as? NSNumber)?.intValue == 3,
              (manifestObject["pluginID"] as? String).flatMap(UUID.init(uuidString:)) == pluginID,
              manifestObject["dylibFileName"] as? String == dylibName,
              manifestObject["plistFileName"] as? String == plistName,
              (manifestObject["dylibSHA256"] as? String)?.caseInsensitiveCompare(SHA256Digest.hex(dylib)) == .orderedSame,
              (manifestObject["plistSHA256"] as? String)?.caseInsensitiveCompare(SHA256Digest.hex(plist)) == .orderedSame,
              (manifestObject["hardBoundBundleIdentifier"] as? String)?.isEmpty == false,
              manifestObject["softAssociatedBundleIdentifiers"] as? [String] != nil,
              (manifestObject["machOIdentitySHA256"] as? String).map(HelperPolicy.isValidHash) == true else {
            throw TransactionError.invalidInput
        }
        let manifestName = String(dylibName.dropLast(6)) + ".fk.json"
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        guard try loadJournal(fd) == nil else { throw TransactionError.manualIntervention }
        let oldDylib = try hashIfPresent(fd, dylibName)
        let oldPlist = try hashIfPresent(fd, plistName)
        let oldManifest = try hashIfPresent(fd, manifestName)
        if oldManifest != nil { try validateManifestMode(fd, manifestName) }
        switch route {
        case .firstInstall:
            guard oldDylib == nil, oldPlist == nil, oldManifest == nil, expectedPrevious == nil else { throw TransactionError.conflict }
        case .update:
            guard let expectedPrevious, oldDylib == expectedPrevious.dylib.lowercased(),
                  oldPlist == expectedPrevious.plist.lowercased(), oldManifest == expectedPrevious.manifest.lowercased(),
                  oldDylib != nil, oldPlist != nil, oldManifest != nil else { throw TransactionError.conflict }
        }
        let tx = UUID()
        let reservedLeaves = [
            ".fk-\(tx.uuidString.lowercased()).dylib.tmp", ".fk-\(tx.uuidString.lowercased()).plist.tmp",
            ".fk-\(tx.uuidString.lowercased()).manifest.tmp", ".fk-\(tx.uuidString.lowercased()).dylib.bak",
            ".fk-\(tx.uuidString.lowercased()).plist.bak", ".fk-\(tx.uuidString.lowercased()).manifest.bak"
        ]
        for leaf in reservedLeaves { try requireAbsentLeaf(fd, leaf) }
        var journal = Journal(schemaVersion: 1, transactionID: tx, pluginID: pluginID,
            dylibName: dylibName, plistName: plistName, manifestName: manifestName,
            newDylibHash: SHA256Digest.hex(dylib), newPlistHash: SHA256Digest.hex(plist),
            newManifestHash: SHA256Digest.hex(manifest), oldDylibHash: oldDylib,
            oldPlistHash: oldPlist, oldManifestHash: oldManifest, phase: .prepared)
        try saveJournal(journal, fd: fd)
        do {
            try crashIfRequested(.prepared, simulateCrashAfter)
            try writeTemp(dylib, name: journal.tempDylib, fd: fd, mode: 0o644)
            try writeTemp(plist, name: journal.tempPlist, fd: fd, mode: 0o644)
            try writeTemp(manifest, name: journal.tempManifest, fd: fd, mode: 0o600)
            journal.phase = .backingUp; try saveJournal(journal, fd: fd); try crashIfRequested(.backingUp, simulateCrashAfter)
            if let oldDylib {
                guard try hashIfPresent(fd, dylibName) == oldDylib else { throw TransactionError.conflict }
                try requireAbsentLeaf(fd, journal.backupDylib); try move(dylibName, journal.backupDylib, fd: fd)
            }
            if let oldPlist {
                guard try hashIfPresent(fd, plistName) == oldPlist else { throw TransactionError.conflict }
                try requireAbsentLeaf(fd, journal.backupPlist); try move(plistName, journal.backupPlist, fd: fd)
            }
            if let oldManifest {
                guard try hashIfPresent(fd, manifestName) == oldManifest else { throw TransactionError.conflict }
                try requireAbsentLeaf(fd, journal.backupManifest); try move(manifestName, journal.backupManifest, fd: fd)
            }
            guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
            journal.phase = .installingDylib; try saveJournal(journal, fd: fd); try crashIfRequested(.installingDylib, simulateCrashAfter)
            try requireAbsentLeaf(fd, dylibName); try move(journal.tempDylib, dylibName, fd: fd)
            journal.phase = .installingPlist; try saveJournal(journal, fd: fd); try crashIfRequested(.installingPlist, simulateCrashAfter)
            try requireAbsentLeaf(fd, plistName); try move(journal.tempPlist, plistName, fd: fd)
            journal.phase = .installingManifest; try saveJournal(journal, fd: fd); try crashIfRequested(.installingManifest, simulateCrashAfter)
            try requireAbsentLeaf(fd, manifestName); try move(journal.tempManifest, manifestName, fd: fd)
            guard try hashIfPresent(fd, dylibName) == journal.newDylibHash,
                  try hashIfPresent(fd, plistName) == journal.newPlistHash,
                  try hashIfPresent(fd, manifestName) == journal.newManifestHash,
                  fsync(fd) == 0 else { throw TransactionError.hashMismatch }
            try validateManifestMode(fd, manifestName)
            journal.phase = .committed; try saveJournal(journal, fd: fd); try crashIfRequested(.committed, simulateCrashAfter)
            try cleanupCommitted(journal, fd: fd)
            let routeName: String
            switch route { case .firstInstall: routeName = "firstInstall"; case .update: routeName = "update" }
            return Receipt(transactionID: tx, pluginID: pluginID, route: routeName,
                dylibSHA256: journal.newDylibHash, plistSHA256: journal.newPlistHash,
                manifestSHA256: journal.newManifestHash, completedAt: Date())
        } catch let error as TransactionError {
            if case .injectedCrash = error { throw error }
            let reconciled = try reconcileLocked(fd: fd)
            if journal.phase == .committed && reconciled {
                let routeName = route == .firstInstall ? "firstInstall" : "update"
                return Receipt(transactionID: tx, pluginID: pluginID, route: routeName,
                    dylibSHA256: journal.newDylibHash, plistSHA256: journal.newPlistHash,
                    manifestSHA256: journal.newManifestHash, completedAt: Date())
            }
            throw error
        } catch {
            let reconciled = try reconcileLocked(fd: fd)
            if journal.phase == .committed && reconciled {
                let routeName = route == .firstInstall ? "firstInstall" : "update"
                return Receipt(transactionID: tx, pluginID: pluginID, route: routeName,
                    dylibSHA256: journal.newDylibHash, plistSHA256: journal.newPlistHash,
                    manifestSHA256: journal.newManifestHash, completedAt: Date())
            }
            throw TransactionError.io(errno)
        }
    }

    /// Read-only startup probe. A pending journal is reported to the Runtime, which exposes status-only IPC and blocks
    /// deployment requests; this method never mutates target files.
    func inspectPendingJournal() throws -> Bool {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        return try loadJournal(fd) != nil
    }

    /// Explicit, root-only reconciliation. Runtime startup intentionally calls only
    /// inspectPendingJournal(); this mutating API must be invoked by a separately authorized
    /// recovery workflow after the operator/device policy permits filesystem repair.
    /// It never guesses: any foreign hash leaves the journal intact for manual intervention.
    func reconcile() throws -> Bool {
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        guard geteuid() == 0 else { throw TransactionError.notRoot }
        let fd = try openDirectory(); defer { _ = close(fd) }
        try validateDirectory(fd)
        return try reconcileLocked(fd: fd)
    }

    private func reconcileLocked(fd: Int32) throws -> Bool {
        guard let j = try loadJournal(fd) else { return false }
        try j.validate()
        let committed = j.phase == .committed
        let currentD = try hashIfPresent(fd, j.dylibName), currentP = try hashIfPresent(fd, j.plistName), currentM = try hashIfPresent(fd, j.manifestName)
        let backupD = try hashIfPresent(fd, j.backupDylib), backupP = try hashIfPresent(fd, j.backupPlist), backupM = try hashIfPresent(fd, j.backupManifest)
        let tempD = try hashIfPresent(fd, j.tempDylib), tempP = try hashIfPresent(fd, j.tempPlist), tempM = try hashIfPresent(fd, j.tempManifest)
        for (actual, expected) in [(backupD, j.oldDylibHash), (backupP, j.oldPlistHash), (backupM, j.oldManifestHash)] where actual != nil && actual != expected {
            throw TransactionError.manualIntervention
        }
        if currentM != nil { try validateManifestMode(fd, j.manifestName) }
        if backupM != nil { try validateManifestMode(fd, j.backupManifest) }
        if tempM != nil { try validateManifestMode(fd, j.tempManifest) }
        for (actual, expected) in [(tempD, j.newDylibHash), (tempP, j.newPlistHash), (tempM, j.newManifestHash)] where actual != nil && actual != expected {
            throw TransactionError.manualIntervention
        }
        if committed {
            guard currentD == j.newDylibHash, currentP == j.newPlistHash, currentM == j.newManifestHash else { throw TransactionError.manualIntervention }
            try removeIfHash(fd, j.backupDylib, j.oldDylibHash)
            try removeIfHash(fd, j.backupPlist, j.oldPlistHash)
            try removeIfHash(fd, j.backupManifest, j.oldManifestHash)
        } else {
            // Validate each destination as either old, new, or absent for first install.
            for (actual, old, new) in [(currentD, j.oldDylibHash, j.newDylibHash), (currentP, j.oldPlistHash, j.newPlistHash), (currentM, j.oldManifestHash, j.newManifestHash)] {
                if let actual, actual != old && actual != new { throw TransactionError.manualIntervention }
            }
            try rollbackOne(fd, destination: j.dylibName, backup: j.backupDylib, oldHash: j.oldDylibHash, newHash: j.newDylibHash)
            try rollbackOne(fd, destination: j.plistName, backup: j.backupPlist, oldHash: j.oldPlistHash, newHash: j.newPlistHash)
            try rollbackOne(fd, destination: j.manifestName, backup: j.backupManifest, oldHash: j.oldManifestHash, newHash: j.newManifestHash)
        }
        try removeIfHash(fd, j.tempDylib, j.newDylibHash)
        try removeIfHash(fd, j.tempPlist, j.newPlistHash)
        try removeIfHash(fd, j.tempManifest, j.newManifestHash)
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
        try clearJournal(fd)
        return true
    }

    private func rollbackOne(_ fd: Int32, destination: String, backup: String, oldHash: String?, newHash: String) throws {
        let current = try hashIfPresent(fd, destination), oldBackup = try hashIfPresent(fd, backup)
        if let current, current == newHash { try unlinkLeaf(fd, destination) }
        else if let current, current != oldHash { throw TransactionError.manualIntervention }
        if let oldHash {
            if oldBackup == oldHash {
                if try hashIfPresent(fd, destination) != nil { throw TransactionError.manualIntervention }
                try move(backup, destination, fd: fd)
            } else if try hashIfPresent(fd, destination) != oldHash { throw TransactionError.manualIntervention }
        } else if oldBackup != nil { throw TransactionError.manualIntervention }
    }

    private func cleanupCommitted(_ j: Journal, fd: Int32) throws {
        try removeIfHash(fd, j.backupDylib, j.oldDylibHash)
        try removeIfHash(fd, j.backupPlist, j.oldPlistHash)
        try removeIfHash(fd, j.backupManifest, j.oldManifestHash)
        try removeIfHash(fd, j.tempDylib, j.newDylibHash)
        try removeIfHash(fd, j.tempPlist, j.newPlistHash)
        try removeIfHash(fd, j.tempManifest, j.newManifestHash)
        guard fsync(fd) == 0 else { throw TransactionError.io(errno) }
        try clearJournal(fd)
    }

    private func crashIfRequested(_ phase: Phase, _ requested: Phase?) throws {
        if requested == phase { throw TransactionError.injectedCrash(phase) }
    }
    private func hashIfPresent(_ fd: Int32, _ leaf: String) throws -> String? {
        var pathInfo = stat()
        let rc = leaf.withCString { fstatat(fd, $0, &pathInfo, AT_SYMLINK_NOFOLLOW) }
        if rc != 0 { if errno == ENOENT { return nil }; throw TransactionError.unsafeFile }
        guard (pathInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              pathInfo.st_uid == 0, pathInfo.st_gid == 0, pathInfo.st_nlink == 1,
              (pathInfo.st_mode & 0o6022) == 0,
              pathInfo.st_size >= 0, pathInfo.st_size <= 64 * 1024 * 1024 else {
            throw TransactionError.unsafeFile
        }
        let f = leaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard f >= 0 else { throw TransactionError.unsafeFile }
        defer { _ = close(f) }
        var openedInfo = stat()
        guard fstat(f, &openedInfo) == 0,
              openedInfo.st_dev == pathInfo.st_dev, openedInfo.st_ino == pathInfo.st_ino,
              openedInfo.st_uid == 0, openedInfo.st_gid == 0, openedInfo.st_nlink == 1,
              (openedInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              (openedInfo.st_mode & 0o6022) == 0,
              openedInfo.st_size == pathInfo.st_size else { throw TransactionError.unsafeFile }
        var data = Data(); data.reserveCapacity(Int(openedInfo.st_size))
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(f, &buf, buf.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw TransactionError.io(errno) }
            if n == 0 { break }
            data.append(contentsOf: buf.prefix(n))
            guard data.count <= 64 * 1024 * 1024 else { throw TransactionError.unsafeFile }
        }
        var finalInfo = stat()
        guard fstat(f, &finalInfo) == 0,
              finalInfo.st_dev == openedInfo.st_dev, finalInfo.st_ino == openedInfo.st_ino,
              finalInfo.st_uid == openedInfo.st_uid, finalInfo.st_gid == openedInfo.st_gid,
              finalInfo.st_nlink == 1, finalInfo.st_mode == openedInfo.st_mode,
              finalInfo.st_size == openedInfo.st_size,
              data.count == finalInfo.st_size else { throw TransactionError.unsafeFile }
        return SHA256Digest.hex(data)
    }
    private func validateManifestMode(_ fd: Int32, _ leaf: String) throws {
        var st = stat()
        guard leaf.withCString({ fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }) == 0,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0,
              (st.st_mode & 0o777) == 0o600, (st.st_mode & 0o6000) == 0,
              st.st_nlink == 1 else { throw TransactionError.unsafeFile }
        let fileFD = leaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fileFD >= 0 else { throw TransactionError.unsafeFile }
        defer { _ = close(fileFD) }
        var opened = stat()
        guard fstat(fileFD, &opened) == 0, opened.st_dev == st.st_dev, opened.st_ino == st.st_ino,
              opened.st_uid == 0, opened.st_gid == 0,
              (opened.st_mode & 0o777) == 0o600 else { throw TransactionError.unsafeFile }
    }
    private func writeTemp(_ data: Data, name: String, fd: Int32, mode: mode_t) throws {
        let f = name.withCString { openat(fd, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard f >= 0 else { throw TransactionError.io(errno) }
        var complete = false
        defer {
            _ = close(f)
            if !complete { _ = name.withCString { unlinkat(fd, $0, 0) } }
        }
        try data.withUnsafeBytes { raw in guard let p = raw.baseAddress else { return }; var off = 0; while off < raw.count { let n = write(f, p.advanced(by: off), raw.count - off); if n < 0 && errno == EINTR { continue }; guard n > 0 else { throw TransactionError.io(errno) }; off += n } }
        guard fchown(f, 0, 0) == 0, fchmod(f, mode) == 0, fsync(f) == 0 else { throw TransactionError.io(errno) }
        complete = true
    }
    private func requireAbsentLeaf(_ fd: Int32, _ leaf: String) throws {
        var st = stat()
        let rc = leaf.withCString { fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }
        if rc == 0 { throw TransactionError.conflict }
        guard errno == ENOENT else { throw TransactionError.unsafeFile }
    }
    private func move(_ from: String, _ to: String, fd: Int32) throws {
        let rc = from.withCString { a in to.withCString { b in renameat(fd, a, fd, b) } }
        guard rc == 0 else { throw TransactionError.io(errno) }
    }
    private func unlinkLeaf(_ fd: Int32, _ leaf: String) throws { let rc = leaf.withCString { unlinkat(fd, $0, 0) }; guard rc == 0 else { throw TransactionError.io(errno) } }
    private func removeIfHash(_ fd: Int32, _ leaf: String, _ expected: String?) throws {
        guard let expected else { return }; guard let actual = try hashIfPresent(fd, leaf) else { return }; guard actual == expected else { throw TransactionError.manualIntervention }; try unlinkLeaf(fd, leaf)
    }
    private func openDirectory() throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC); guard fd >= 0 else { throw TransactionError.io(errno) }
        for c in directoryPath.split(separator: "/").map(String.init) { let n = c.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }; guard n >= 0 else { let e = errno; _ = close(fd); throw TransactionError.io(e) }; _ = close(fd); fd = n }
        return fd
    }
    private func validateDirectory(_ fd: Int32) throws { var st = stat(); guard fstat(fd, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR), st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o022) == 0 else { throw TransactionError.unsafeDirectory } }
    private func loadJournal(_ fd: Int32) throws -> Journal? {
        let f = journalLeaf.withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }; if f < 0 { if errno == ENOENT { return nil }; throw TransactionError.io(errno) }; defer { _ = close(f) }
        var st = stat(); guard fstat(f, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0, (st.st_mode & 0o777) == 0o600, st.st_size >= 0, st.st_size <= 32 * 1024 else { throw TransactionError.journalInvalid }
        let d = try readAll(f, limit: 32 * 1024); guard let j = try? JSONDecoder().decode(Journal.self, from: d) else { throw TransactionError.journalInvalid }; try j.validate(); return j
    }
    private func saveJournal(_ j: Journal, fd: Int32) throws {
        let data = try JSONEncoder().encode(j); let tmp = ".fk-journal-\(UUID().uuidString.lowercased()).tmp"
        let f = tmp.withCString { openat(fd, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }; guard f >= 0 else { throw TransactionError.io(errno) }; defer { _ = close(f); _ = tmp.withCString { unlinkat(fd, $0, 0) } }
        try writeAll(data, f); guard fchown(f, 0, 0) == 0, fchmod(f, 0o600) == 0, fsync(f) == 0 else { throw TransactionError.io(errno) }
        let rc = tmp.withCString { a in journalLeaf.withCString { b in renameat(fd, a, fd, b) } }; guard rc == 0, fsync(fd) == 0 else { throw TransactionError.io(errno) }
    }
    private func clearJournal(_ fd: Int32) throws { var st = stat(); let rc = journalLeaf.withCString { fstatat(fd, $0, &st, AT_SYMLINK_NOFOLLOW) }; if rc == 0 { guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), st.st_uid == 0, st.st_gid == 0, st.st_nlink == 1, (st.st_mode & 0o777) == 0o600 else { throw TransactionError.journalInvalid }; let u = journalLeaf.withCString { unlinkat(fd, $0, 0) }; guard u == 0 else { throw TransactionError.io(errno) } } else if errno != ENOENT { throw TransactionError.io(errno) }; guard fsync(fd) == 0 else { throw TransactionError.io(errno) } }
    private func readAll(_ fd: Int32, limit: Int) throws -> Data { var d = Data(); var b = [UInt8](repeating: 0, count: 4096); while true { let n = read(fd, &b, b.count); if n < 0 && errno == EINTR { continue }; guard n >= 0 else { throw TransactionError.io(errno) }; if n == 0 { break }; d.append(contentsOf: b.prefix(n)); guard d.count <= limit else { throw TransactionError.journalInvalid } }; return d }
    private func writeAll(_ d: Data, _ fd: Int32) throws { try d.withUnsafeBytes { raw in guard let p = raw.baseAddress else { return }; var o = 0; while o < raw.count { let n = write(fd, p.advanced(by: o), raw.count-o); if n < 0 && errno == EINTR { continue }; guard n > 0 else { throw TransactionError.io(errno) }; o += n } } }
}
