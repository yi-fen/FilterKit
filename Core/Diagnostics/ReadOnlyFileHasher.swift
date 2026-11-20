//
// ReadOnlyFileHasher.swift
// 0.1.18 reference port — streaming MD5/SHA-256 helper.
// MD5 is for dpkg .md5sums compatibility only, never a security signature.
// SHA-256 is exposed for verifying a backup copy against its source snapshot.
//

import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public struct FKFileHashSnapshot: Codable, Equatable {
    public let path: String
    public let byteCount: UInt64
    public let md5: String?
    public let sha256: String?
}

public enum ReadOnlyFileHasher {
    /// Reads the file in bounded chunks and computes both digests in one pass.
    /// This function never writes to the input path.
    public static func hashFile(at url: URL, chunkSize: Int = 64 * 1024) -> FKFileHashSnapshot? {
        #if canImport(CommonCrypto)
        guard chunkSize > 0, let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var md5Context = CC_MD5_CTX()
        var shaContext = CC_SHA256_CTX()
        CC_MD5_Init(&md5Context)
        CC_SHA256_Init(&shaContext)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var total: UInt64 = 0
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            total += UInt64(count)
            buffer.withUnsafeBytes { rawBuffer in
                _ = CC_MD5_Update(&md5Context, rawBuffer.baseAddress!, CC_LONG(count))
                _ = CC_SHA256_Update(&shaContext, rawBuffer.baseAddress!, CC_LONG(count))
            }
        }
        var md5Bytes = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        var shaBytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        md5Bytes.withUnsafeMutableBufferPointer { output in
            _ = CC_MD5_Final(output.baseAddress!, &md5Context)
        }
        shaBytes.withUnsafeMutableBufferPointer { output in
            _ = CC_SHA256_Final(output.baseAddress!, &shaContext)
        }
        return FKFileHashSnapshot(path: url.path, byteCount: total,
            md5: md5Bytes.map { String(format: "%02x", $0) }.joined(),
            sha256: shaBytes.map { String(format: "%02x", $0) }.joined())
        #else
        return nil
        #endif
    }

    /// Compares two independently hashed files; no file is copied or restored.
    public static func matches(_ lhs: URL, _ rhs: URL) -> Bool? {
        guard let left = hashFile(at: lhs), let right = hashFile(at: rhs),
              let leftSHA = left.sha256, let rightSHA = right.sha256 else { return nil }
        return left.byteCount == right.byteCount && leftSHA == rightSHA
    }
}
