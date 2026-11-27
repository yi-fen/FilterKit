// Compile-only importer probe for the Darwin APIs used by FilterKit's Helper IPC.
// Run with xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -typecheck ...
import Foundation
import Darwin
import libproc

@_silgen_name("csops")
private func filterKitProbeCSOps(_ pid: pid_t, _ operation: UInt32,
                                 _ output: UnsafeMutableRawPointer?, _ outputLength: Int) -> Int32

func filterKitDarwinSDKCompileProbe(_ pid: pid_t, _ fd: Int32) {
    // Socket peer UID/GID and PID APIs used by UnixDomainSocketTransport.
    var peerUID: uid_t = 0
    var peerGID: gid_t = 0
    _ = getpeereid(fd, &peerUID, &peerGID)
    var peerPID: pid_t = -1
    var peerPIDLength = socklen_t(MemoryLayout<pid_t>.size)
    _ = getsockopt(fd, 0, 0x002, &peerPID, &peerPIDLength) // SOL_LOCAL / LOCAL_PEERPID

    // Opaque LOCAL_PEERTOKEN snapshot used by DarwinPeerIdentityProvider.
    var auditToken = [UInt32](repeating: 0, count: 8)
    var auditTokenLength = socklen_t(MemoryLayout<UInt32>.size * auditToken.count)
    _ = auditToken.withUnsafeMutableBytes {
        getsockopt(fd, 0, 0x003, $0.baseAddress, &auditTokenLength) // SOL_LOCAL / LOCAL_PEERTOKEN
    }

    // csops(CS_OPS_CDHASH) link availability is verified by the full Helper target build;
    // this typecheck probe verifies the Swift call signature without executing the syscall.
    var cdHash = [UInt8](repeating: 0, count: 20)
    _ = cdHash.withUnsafeMutableBytes {
        filterKitProbeCSOps(pid, 5, $0.baseAddress, $0.count) // CS_OPS_CDHASH / CS_CDHASH_LEN
    }

    // Existing process inspection SDK surface used by the optional generation diagnostics.
    var processInfo = proc_bsdinfo()
    let processInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    _ = withUnsafeMutablePointer(to: &processInfo) { pointer in
        pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<proc_bsdinfo>.size) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, processInfoSize)
        }
    }
    _ = (peerUID, peerGID, peerPID, auditToken, cdHash, processInfo.pbi_pid)
}
