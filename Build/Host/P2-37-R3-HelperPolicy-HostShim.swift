import Foundation

/// Host-only validation shim. Production uses the real HelperPolicy implementation.
enum HelperPolicy {
    static func isSafeLeafName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    static func isValidHash(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}
