import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func require129(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-29", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
@main struct P129StagingReaderSmoke {
    static func main() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p1-29-\(UUID().uuidString)", isDirectory: true)
        let staging = base.appendingPathComponent("staging", isDirectory: true)
        let task = staging.appendingPathComponent("task", isDirectory: true)
        try fm.createDirectory(at: task, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: base) }
        let bytes = Data("root-side staging payload".utf8)
        let payload = task.appendingPathComponent("Demo.dylib")
        try bytes.write(to: payload)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: payload.path)
        let reader = try HelperStagingPayloadReader(rootPath: staging.path, expectedOwner: UInt32(getuid()))
        let readBack = try reader.read(relativePath: "task/Demo.dylib")
        try require129(readBack == bytes, "regular staged payload read mismatch")
        let symlink = task.appendingPathComponent("Link.dylib")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: payload)
        do {
            _ = try reader.read(relativePath: "task/Link.dylib")
            throw NSError(domain: "P1-29", code: 2, userInfo: [NSLocalizedDescriptionKey: "staging symlink accepted"])
        } catch HelperStagingPayloadReader.ReaderError.unsafeFile { }
        do {
            _ = try reader.read(relativePath: "../outside")
            throw NSError(domain: "P1-29", code: 3, userInfo: [NSLocalizedDescriptionKey: "path traversal accepted"])
        } catch HelperStagingPayloadReader.ReaderError.invalidPath { }
        print("P1-29 staging reader smoke: PASS (fd-relative read, no-follow file, traversal rejection)")
    }
}
