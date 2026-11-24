import Foundation

/// Verifies the kernel-reported identity of the running Helper against the installer-pinned CDHash.
/// The kernel only reports a CDHash for the currently executing code-signing identity; this does
/// not establish publisher/team provenance by itself.
struct HelperCodeSignatureVerifier {
    enum VerificationError: Error, Equatable {
        case malformedExpectedCDHash
        case runningCDHashMismatch
        case invalidExecutablePath
        case staticVerificationUnavailable
        case staticSignatureInvalid
        case staticCDHashMismatch
    }

    func verifyRunningHelper(cdHash: String, allowedCDHashes: [String]) throws {
        guard HelperPolicy.isValidCDHash(cdHash),
              !allowedCDHashes.isEmpty,
              allowedCDHashes.allSatisfy(HelperPolicy.isValidCDHash) else {
            throw VerificationError.malformedExpectedCDHash
        }
        guard allowedCDHashes.contains(where: { $0.caseInsensitiveCompare(cdHash) == .orderedSame }) else {
            throw VerificationError.runningCDHashMismatch
        }
    }

    /// Static code validation is currently implemented for macOS tooling only. iOS/jailbreak
    /// startup uses the kernel-reported running-process CDHash above and fails closed if a caller
    /// requests static validation on an unsupported platform.
    func verifyStaticExecutable(at path: String, expectedCDHash: String) throws {
        guard path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/").contains(".."),
              HelperPolicy.isValidCDHash(expectedCDHash) else {
            throw VerificationError.invalidExecutablePath
        }
        #if os(macOS) && canImport(Security)
        importSecurityStaticCodeVerification(path: path, expectedCDHash: expectedCDHash)
        #else
        throw VerificationError.staticVerificationUnavailable
        #endif
    }
}

#if os(macOS) && canImport(Security)
import Security

private func importSecurityStaticCodeVerification(path: String, expectedCDHash: String) throws {
    var staticCode: SecStaticCode?
    let url = URL(fileURLWithPath: path, isDirectory: false) as CFURL
    guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
          let code = staticCode else {
        throw HelperCodeSignatureVerifier.VerificationError.staticSignatureInvalid
    }
    guard SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else {
        throw HelperCodeSignatureVerifier.VerificationError.staticSignatureInvalid
    }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let dictionary = information as? [String: Any],
          let unique = dictionary[kSecCodeInfoUnique as String] as? Data else {
        throw HelperCodeSignatureVerifier.VerificationError.staticSignatureInvalid
    }
    let actual = unique.map { String(format: "%02x", $0) }.joined()
    guard actual.caseInsensitiveCompare(expectedCDHash) == .orderedSame else {
        throw HelperCodeSignatureVerifier.VerificationError.staticCDHashMismatch
    }
}
#endif
