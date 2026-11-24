import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
enum FilterKitHelperMain {
    static func main() {
        do {
            try FilterKitHelperRuntime().run()
        } catch {
            // Startup errors are intentionally terse; detailed diagnostics belong in the
            // privileged installer's audit channel, not in an unauthenticated socket response.
            FileHandle.standardError.write(Data("FilterKitHelper: startup refused (\(String(describing: error)))\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
