import Foundation

/// Recovery and release acceptance serialize on the exact persistent lock inode already used
/// by HelperRootAtomicActivationExecutor: <JBROOT>/.filterkit-root-activation.lock.
/// The lock is intentionally not removed. A caller must hold it across both evidence passes and
/// any separately authorized operation; this API itself exposes no mutation primitive.
enum HelperInstallerSharedTransactionLock {
    enum LockError: Error, Equatable { case invalidRoot }

    static func withExclusiveLock<T>(jbroot: String, body: () throws -> T) throws -> T {
        guard HelperPolicy.isAbsoluteCleanPath(jbroot), jbroot != "/" else { throw LockError.invalidRoot }
        return try HelperReleaseAcceptanceLock.withLock(root: jbroot, body: body)
    }
}
