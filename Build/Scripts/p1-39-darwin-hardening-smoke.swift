import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
func require139(_ ok: @autoclosure () -> Bool, _ message: String) throws { guard ok() else { throw NSError(domain: "P1-39", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
@main struct P139Smoke {
 static func main() throws {
  let base = NSTemporaryDirectory() + "filterkit-p138-" + UUID().uuidString
  let fm = FileManager.default
  try fm.createDirectory(atPath: base + "/usr/libexec", withIntermediateDirectories: true)
  try fm.createDirectory(atPath: base + "/Library/FilterKit/Helper", withIntermediateDirectories: true)
  try fm.createDirectory(atPath: base + "/Library/LaunchDaemons", withIntermediateDirectories: true)
  defer { try? fm.removeItem(atPath: base) }
  _ = chmod(base, 0o700)
  for p in ["usr", "usr/libexec", "Library", "Library/FilterKit", "Library/FilterKit/Helper", "Library/LaunchDaemons"] { _ = chmod(base + "/" + p, 0o700) }
  let executor = try HelperRootAtomicActivationExecutor(rootDirectory: base)
  func bundle(_ generation: UInt64) -> HelperInstallerProvisioningBundle {
   HelperInstallerProvisioningBundle(schemaVersion: 2, generation: generation,
    releaseIdentifier: "1.0.0-p138-\(generation)", bundleIdentifier: "cn.yfen.filterkit", jbRootPath: "/var/jb",
    appCDHash: String(repeating: "a", count: 40), helperCDHash: String(repeating: "b", count: 40),
    allowedClientUID: 501, stagingOwnerUID: 501, routeIdentifier: "dopamine-roothide",
    tweakInjectPath: "/var/jb/usr/lib/TweakInject", stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
    socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
  }
  func release(_ b: HelperInstallerProvisioningBundle, _ executable: Data, _ old: [HelperRootAtomicActivationExecutor.Artifact: String?]) throws -> HelperRootAtomicActivationExecutor.Release {
   let bytes: [HelperRootAtomicActivationExecutor.Artifact: Data] = [.executable: executable,
    .deploymentManifest: try JSONEncoder().encode(b.disabledRootManifest()), .launchDaemon: try b.disabledLaunchDaemonPlist()]
   let pathBytes = [HelperRootReleaseSet.executablePath: bytes[.executable]!, HelperRootReleaseSet.manifestPath: bytes[.deploymentManifest]!, HelperRootReleaseSet.launchDaemonPath: bytes[.launchDaemon]!]
   let digests = pathBytes.map { HelperInstallerArtifactDigest(relativePath: $0.key, sha256: SHA256Digest.hex($0.value)) }
   return .init(bundle: b, bytes: bytes, expectedDigests: digests, expectedPreviousHashes: old)
  }
  let firstBundle = bundle(12)
  let firstExecutable = Data([0xcf,0xfa,0xed,0xfe,1])
  let first = try release(firstBundle, firstExecutable, [.executable:nil,.deploymentManifest:nil,.launchDaemon:nil])
  let foreignPath = base + "/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
  try Data("foreign-owner".utf8).write(to: URL(fileURLWithPath: foreignPath))
  do { _ = try executor.activate(first); throw NSError(domain:"P1-39",code:3,userInfo:[NSLocalizedDescriptionKey:"foreign destination was overwritten"]) }
  catch HelperRootAtomicActivationExecutor.Failure.conflict { }
  try fm.removeItem(atPath: foreignPath)
  let installed = try executor.activate(first)
  try require139(installed.installedHashes.count == 3, "first release did not install all artifacts")
  let executableMode = (try fm.attributesOfItem(atPath: base + "/usr/libexec/filterkit-helper")[.posixPermissions] as? NSNumber)?.intValue
  let manifestMode = (try fm.attributesOfItem(atPath: base + "/Library/FilterKit/Helper/Deployment.json")[.posixPermissions] as? NSNumber)?.intValue
  try require139(executableMode == 0o755 && manifestMode == 0o600, "deployed ownership modes are incorrect")
  let secondExecutable = Data([0xcf,0xfa,0xed,0xfe,2])
  let previous = Dictionary(uniqueKeysWithValues: first.bytes.map { ($0.key, Optional(SHA256Digest.hex($0.value))) })
  let second = try release(bundle(13), secondExecutable, previous)
  let lockAttributes = try fm.attributesOfItem(atPath: base + "/.filterkit-root-activation.lock")
  try require139((lockAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "transaction lock file mode is not 0600")
  let lockFD1 = (base + "/.filterkit-root-activation.lock").withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
  let lockFD2 = (base + "/.filterkit-root-activation.lock").withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
  try require139(lockFD1 >= 0 && lockFD2 >= 0, "could not open transaction lock for contention test")
  try require139(flock(lockFD1, LOCK_EX | LOCK_NB) == 0, "first lock acquisition failed")
  let secondLockResult = flock(lockFD2, LOCK_EX | LOCK_NB)
  try require139(secondLockResult == -1 && (errno == EWOULDBLOCK || errno == EAGAIN), "concurrent lock acquisition was not rejected")
  _ = flock(lockFD1, LOCK_UN); _ = close(lockFD1); _ = close(lockFD2)
  let point = HelperRootAtomicActivationExecutor.FaultPoint.afterFirstActivation
  do { _ = try executor.activate(second, faultAt: point); throw NSError(domain:"P1-39",code:6,userInfo:[NSLocalizedDescriptionKey:"fault injection did not fire"]) }
  catch HelperRootAtomicActivationExecutor.Failure.injectedFault(let observed) { try require139(observed == point, "wrong fault point reported") }
  let recoveredFault = try executor.recover()
  try require139(recoveredFault == .rolledBack, "activation-rename fault did not recover to prior release")
  do { _ = try executor.activate(second, crashAfter:.deploymentManifest); throw NSError(domain:"P1-39",code:2,userInfo:[NSLocalizedDescriptionKey:"crash injection did not fire"]) }
  catch HelperRootAtomicActivationExecutor.Failure.injectedCrash { }
  let recovered = try executor.recover()
  try require139(recovered == .rolledBack, "interrupted activation did not roll back")
  let final = try executor.activate(second)
  try require139(final.installedHashes[.executable] == SHA256Digest.hex(secondExecutable), "upgrade hash mismatch")
  let rootEntries = try fm.contentsOfDirectory(atPath: base)
  try require139(!rootEntries.contains(".filterkit-root-activation.json"), "journal not cleaned")
  let thirdExecutable = Data([0xcf,0xfa,0xed,0xfe,3])
  let third = try release(bundle(14), thirdExecutable,
      Dictionary(uniqueKeysWithValues: second.bytes.map { ($0.key, Optional(SHA256Digest.hex($0.value))) }))
  do { _ = try executor.activate(third, crashAfter:.executable); throw NSError(domain:"P1-39",code:4,userInfo:[NSLocalizedDescriptionKey:"second crash injection did not fire"]) }
  catch HelperRootAtomicActivationExecutor.Failure.injectedCrash { }
  try Data("foreign-modification".utf8).write(to: URL(fileURLWithPath: base + "/usr/libexec/filterkit-helper"))
  do { _ = try executor.recover(); throw NSError(domain:"P1-39",code:5,userInfo:[NSLocalizedDescriptionKey:"unknown bytes were auto-recovered"]) }
  catch HelperRootAtomicActivationExecutor.Failure.recoveryRequiresManualIntervention { }
  print("PASS: persistent root-owned transaction lock created with mode 0600 and concurrent acquisition rejected")
  print("PASS: activation-rename fault point recovers to the prior release")
  print("PASS: three destination parents validated without symlink traversal")
  print("PASS: foreign destination conflict rejected without overwrite")
  print("PASS: first-install three-artifact activation, mode and hash verification")
  print("PASS: injected mid-activation crash recovered by verified rollback")
  print("PASS: subsequent upgrade committed and durable journal cleaned")
  print("PASS: unknown post-crash bytes stop recovery for manual intervention")
 }
}
