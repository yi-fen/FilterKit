// Compile-only probe for the Darwin APIs used by FilterKit's peer identity provider.
// Run with: xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -typecheck ...
import Foundation
import Darwin
import libproc

func filterKitDarwinSDKCompileProbe(_ pid: pid_t, _ fd: Int32) {
    var info = proc_bsdinfo()
    let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
    _ = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<proc_bsdinfo>.size) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, expected)
        }
    }
    let generation: UInt64 = UInt64(info.pbi_pidversion)
    _ = generation

    var token = [UInt32](repeating: 0, count: 8)
    var length = socklen_t(MemoryLayout<UInt32>.size * token.count)
    _ = token.withUnsafeMutableBytes {
        getsockopt(fd, 0, 0x003, $0.baseAddress, &length)
    }
}
