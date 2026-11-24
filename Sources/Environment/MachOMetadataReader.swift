import Foundation

struct MachOSliceMetadata: Codable, Equatable {
    let architecture: String?
    let cpuType: UInt32
    let cpuSubtype: UInt32
    let is64Bit: Bool
    let installName: String?
    let currentVersion: String?
    let compatibilityVersion: String?
    let uuid: String?
    let cdHash: String?
    let codeSignatureState: String
}

/// Bounds-checked, read-only Mach-O metadata parser. Supports thin and fat containers.
/// It never executes or loads the inspected binary.
struct MachOMetadataReader {
    func read(data: Data, architecture: String? = nil) throws -> ElleKitBinaryVersion {
        let slices = try readSlices(data: data)
        let slice: MachOSliceMetadata
        if let architecture {
            guard let match = slices.first(where: { $0.architecture == architecture }) else {
                throw ElleKitBinaryMetadataError.noSupportedSlice
            }
            slice = match
        } else {
            guard let first = slices.first else { throw ElleKitBinaryMetadataError.noSupportedSlice }
            slice = first
        }
        return ElleKitBinaryVersion(currentVersion: slice.currentVersion,
            compatibilityVersion: slice.compatibilityVersion, installName: slice.installName,
            uuid: slice.uuid, architecture: slice.architecture, is64Bit: slice.is64Bit)
    }

    func readSlices(data: Data) throws -> [MachOSliceMetadata] {
        let b = [UInt8](data)
        guard b.count >= 4 else { throw ElleKitBinaryMetadataError.truncated }
        let magic = u32(b, 0, little: false)
        switch magic {
        case 0xCAFEBABE, 0xCAFEBABF, 0xBEBAFECA, 0xBFBAFECA:
            let little = magic == 0xBEBAFECA || magic == 0xBFBAFECA
            let is64 = magic == 0xCAFEBABF || magic == 0xBFBAFECA
            guard b.count >= 8 else { throw ElleKitBinaryMetadataError.truncated }
            let count = Int(u32(b, 4, little: little))
            let entrySize = is64 ? 32 : 20
            guard count > 0, count <= 128, 8 + count * entrySize <= b.count else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
            var results: [MachOSliceMetadata] = []
            for index in 0..<count {
                let p = 8 + index * entrySize
                let cpu = u32(b, p, little: little), subtype = u32(b, p + 4, little: little)
                let offset = is64 ? Int(u64(b, p + 8, little: little)) : Int(u32(b, p + 8, little: little))
                let size = is64 ? Int(u64(b, p + 16, little: little)) : Int(u32(b, p + 12, little: little))
                guard offset >= 0, size >= 4, offset <= b.count, size <= b.count - offset else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
                let sliceData = Array(b[offset..<(offset + size)])
                if let parsed = try? parseThin(sliceData, fallbackCPU: cpu, fallbackSubtype: subtype) { results.append(parsed) }
            }
            guard !results.isEmpty else { throw ElleKitBinaryMetadataError.noSupportedSlice }
            return results
        default:
            return [try parseThin(b, fallbackCPU: nil, fallbackSubtype: nil)]
        }
    }

    private func parseThin(_ b: [UInt8], fallbackCPU: UInt32?, fallbackSubtype: UInt32?) throws -> MachOSliceMetadata {
        guard b.count >= 4 else { throw ElleKitBinaryMetadataError.truncated }
        let magic = u32(b, 0, little: false)
        let little: Bool, is64: Bool
        switch magic {
        case 0xFEEDFACE: little = false; is64 = false
        case 0xFEEDFACF: little = false; is64 = true
        case 0xCEFAEDFE: little = true; is64 = false
        case 0xCFFAEDFE: little = true; is64 = true
        default: throw ElleKitBinaryMetadataError.notMachO
        }
        let header = is64 ? 32 : 28
        guard b.count >= header else { throw ElleKitBinaryMetadataError.truncated }
        let cpu = u32(b, 4, little: little), subtype = u32(b, 8, little: little) & 0x00ff_ffff
        let actualCPU = fallbackCPU ?? cpu, actualSubtype = fallbackSubtype.map { $0 & 0x00ff_ffff } ?? subtype
        let count = Int(u32(b, 16, little: little)), bytes = Int(u32(b, 20, little: little))
        guard count <= 65535, bytes >= 0, bytes <= b.count - header else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
        var cursor = header, end = header + bytes
        var install: String?, current: String?, compat: String?, uuid: String?
        var signatureRange: Range<Int>?
        for _ in 0..<count {
            guard cursor + 8 <= end else { throw ElleKitBinaryMetadataError.truncated }
            let cmd = u32(b, cursor, little: little), size = Int(u32(b, cursor + 4, little: little))
            guard size >= 8, size <= end - cursor else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
            if cmd == 0xD {
                guard size >= 24 else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
                let nameOffset = Int(u32(b, cursor + 8, little: little))
                if nameOffset >= 24, nameOffset < size { install = cString(b, cursor + nameOffset, cursor + size) }
                current = Self.formatPackedVersion(u32(b, cursor + 16, little: little))
                compat = Self.formatPackedVersion(u32(b, cursor + 20, little: little))
            } else if cmd == 0x1B {
                guard size >= 24 else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
                uuid = b[(cursor + 8)..<(cursor + 24)].map { String(format: "%02x", $0) }.joined()
            } else if cmd == 0x1D {
                guard size >= 16 else { throw ElleKitBinaryMetadataError.malformedLoadCommand }
                let offset = Int(u32(b, cursor + 8, little: little)), length = Int(u32(b, cursor + 12, little: little))
                if offset >= 0, length > 0, offset <= b.count, length <= b.count - offset { signatureRange = offset..<(offset + length) }
            }
            cursor += size
        }
        let cd: (hash: String?, state: String) = signatureRange.map { codeDirectoryHash(Array(b[$0])) } ?? (hash: nil, state: "absent")
        return MachOSliceMetadata(architecture: Self.architectureName(cpuType: actualCPU, cpuSubtype: actualSubtype),
            cpuType: actualCPU, cpuSubtype: actualSubtype, is64Bit: is64, installName: install,
            currentVersion: current, compatibilityVersion: compat, uuid: uuid, cdHash: cd.hash,
            codeSignatureState: cd.state)
    }

    private func codeDirectoryHash(_ blob: [UInt8]) -> (hash: String?, state: String) {
        guard blob.count >= 12 else { return (nil, "malformed") }
        let magic = u32(blob, 0, little: false), length = Int(u32(blob, 4, little: false)), count = Int(u32(blob, 8, little: false))
        guard length >= 12, length <= blob.count else { return (nil, "malformed") }
        let codeDirectories: [Int]
        if magic == 0xFADE0C02 { codeDirectories = [0] }
        else if magic == 0xFADE0CC0 {
            guard count <= 64, 12 + count * 8 <= length else { return (nil, "malformed") }
            codeDirectories = (0..<count).compactMap { i in
                let p = 12 + i * 8
                let off = Int(u32(blob, p + 4, little: false))
                guard off >= 0, off + 8 <= length, u32(blob, off, little: false) == 0xFADE0C02 else { return nil }
                return off
            }
        } else { return (nil, "unsupported") }
        for offset in codeDirectories {
            guard offset + 38 <= length else { continue }
            let cdLength = Int(u32(blob, offset + 4, little: false))
            guard cdLength >= 38, offset + cdLength <= length else { continue }
            let hashSize = Int(blob[offset + 36]), hashType = blob[offset + 37]
            let cd = Data(blob[offset..<(offset + cdLength)])
            switch hashType {
            case 2, 3:
                let hex = SHA256Digest.hex(cd)
                if (hashType == 2 && hashSize == 32) || (hashType == 3 && hashSize == 20) { return (String(hex.prefix(40)), "cdhash_extracted") }
            case 1:
                let hex = SHA1Digest.hex(cd)
                if hashSize == 20 { return (hex, "cdhash_extracted") }
            default: continue
            }
        }
        return (nil, codeDirectories.isEmpty ? "code_directory_missing" : "unsupported_hash_type")
    }

    private static func architectureName(cpuType: UInt32, cpuSubtype: UInt32) -> String? {
        switch cpuType {
        case 0x0100000c: return cpuSubtype == 2 ? "arm64e" : "arm64"
        case 12: return "arm"
        case 0x01000007: return "x86_64"
        case 7: return "i386"
        default: return nil
        }
    }
    private func u32(_ b: [UInt8], _ p: Int, little: Bool) -> UInt32 {
        let v = UInt32(b[p]) << 24 | UInt32(b[p+1]) << 16 | UInt32(b[p+2]) << 8 | UInt32(b[p+3])
        return little ? v.byteSwapped : v
    }
    private func u64(_ b: [UInt8], _ p: Int, little: Bool) -> UInt64 {
        let a = UInt64(u32(b, p, little: little)), c = UInt64(u32(b, p + 4, little: little))
        return little ? (c << 32) | a : (a << 32) | c
    }
    private func cString(_ b: [UInt8], _ start: Int, _ limit: Int) -> String? {
        guard start >= 0, start < limit, limit <= b.count, let zero = b[start..<limit].firstIndex(of: 0) else { return nil }
        return String(bytes: b[start..<zero], encoding: .utf8)
    }
    static func formatPackedVersion(_ value: UInt32) -> String {
        "\((value >> 16) & 0xffff).\((value >> 8) & 0xff).\(value & 0xff)"
    }
}

private enum SHA1Digest {
    static func hex(_ data: Data) -> String {
        var m = [UInt8](data); let bits = UInt64(m.count) * 8
        m.append(0x80); while m.count % 64 != 56 { m.append(0) }
        for s in stride(from: 56, through: 0, by: -8) { m.append(UInt8((bits >> UInt64(s)) & 255)) }
        var h: [UInt32] = [0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0]
        for base in stride(from: 0, to: m.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 { let p = base + i*4; w[i] = UInt32(m[p])<<24 | UInt32(m[p+1])<<16 | UInt32(m[p+2])<<8 | UInt32(m[p+3]) }
            for i in 16..<80 { let x = w[i-3]^w[i-8]^w[i-14]^w[i-16]; w[i] = (x << 1) | (x >> 31) }
            var a=h[0],b=h[1],c=h[2],d=h[3],e=h[4]
            for i in 0..<80 { let f: UInt32, k: UInt32
                switch i { case 0..<20: f=(b&c)|((~b)&d); k=0x5A827999; case 20..<40: f=b^c^d; k=0x6ED9EBA1; case 40..<60: f=(b&c)|(b&d)|(c&d); k=0x8F1BBCDC; default: f=b^c^d; k=0xCA62C1D6 }
                let t = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]; e=d; d=c; c=(b << 30)|(b >> 2); b=a; a=t
            }
            h[0]&+=a; h[1]&+=b; h[2]&+=c; h[3]&+=d; h[4]&+=e
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
