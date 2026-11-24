import XCTest
@testable import FilterKit

final class MachOMetadataReaderTests: XCTestCase {
    func testThinArm64eExtractsIdentityAndVersions() throws {
        let data = thinMachO(cpu: 0x0100000c, subtype: 2)
        let slices = try MachOMetadataReader().readSlices(data: data)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].architecture, "arm64e")
        XCTAssertEqual(slices[0].installName, "com.example.plugin.dylib")
        XCTAssertEqual(slices[0].currentVersion, "1.2.3")
        XCTAssertEqual(slices[0].compatibilityVersion, "1.0.0")
        XCTAssertEqual(slices[0].uuid, "000102030405060708090a0b0c0d0e0f")
        XCTAssertEqual(slices[0].codeSignatureState, "absent")
    }

    func testFatBinaryEnumeratesEachArchitectureSlice() throws {
        let arm64 = thinMachO(cpu: 0x0100000c, subtype: 0)
        let arm64e = thinMachO(cpu: 0x0100000c, subtype: 2)
        var fat = Data([0xca, 0xfe, 0xba, 0xbe])
        appendBE32(2, to: &fat)
        let firstOffset = 8 + 2 * 20
        appendBE32(0x0100000c, to: &fat); appendBE32(0, to: &fat)
        appendBE32(UInt32(firstOffset), to: &fat); appendBE32(UInt32(arm64.count), to: &fat); appendBE32(0, to: &fat)
        let secondOffset = firstOffset + arm64.count
        appendBE32(0x0100000c, to: &fat); appendBE32(2, to: &fat)
        appendBE32(UInt32(secondOffset), to: &fat); appendBE32(UInt32(arm64e.count), to: &fat); appendBE32(0, to: &fat)
        fat.append(arm64); fat.append(arm64e)
        let slices = try MachOMetadataReader().readSlices(data: fat)
        XCTAssertEqual(slices.map(\.architecture), ["arm64", "arm64e"])
    }

    func testRejectsTruncatedLoadCommand() {
        XCTAssertThrowsError(try MachOMetadataReader().readSlices(data: Data([0xcf, 0xfa, 0xed, 0xfe])))
    }


    func testCodeDirectoryCDHashIsExtracted() throws {
        let data = thinMachOWithCodeSignature()
        let slice = try XCTUnwrap(MachOMetadataReader().readSlices(data: data).first)
        XCTAssertEqual(slice.codeSignatureState, "cdhash_extracted")
        XCTAssertEqual(slice.cdHash?.count, 40)
    }

    private func thinMachOWithCodeSignature() -> Data {
        var d = Data([0xcf, 0xfa, 0xed, 0xfe])
        appendLE32(0x0100000c, to: &d); appendLE32(2, to: &d)
        appendLE32(6, to: &d); appendLE32(3, to: &d); appendLE32(92, to: &d)
        appendLE32(0, to: &d); appendLE32(0, to: &d)
        appendLE32(0x0d, to: &d); appendLE32(52, to: &d); appendLE32(24, to: &d)
        appendLE32(0, to: &d); appendLE32(0x00010203, to: &d); appendLE32(0x00010000, to: &d)
        d.append(Data("com.example.plugin.dylib\0".utf8)); while d.count < 84 { d.append(0) }
        appendLE32(0x1b, to: &d); appendLE32(24, to: &d); d.append(contentsOf: (0..<16).map(UInt8.init))
        appendLE32(0x1d, to: &d); appendLE32(16, to: &d); appendLE32(124, to: &d); appendLE32(60, to: &d)
        appendBE32(0xFADE0CC0, to: &d); appendBE32(60, to: &d); appendBE32(1, to: &d)
        appendBE32(0, to: &d); appendBE32(20, to: &d)
        appendBE32(0xFADE0C02, to: &d); appendBE32(40, to: &d)
        appendBE32(0x00020001, to: &d); appendBE32(0, to: &d)
        appendBE32(40, to: &d); appendBE32(0, to: &d)
        appendBE32(0, to: &d); appendBE32(0, to: &d); appendBE32(0, to: &d)
        d.append(32); d.append(2); d.append(0); d.append(0)
        return d
    }

    private func thinMachO(cpu: UInt32, subtype: UInt32) -> Data {
        var d = Data([0xcf, 0xfa, 0xed, 0xfe])
        appendLE32(cpu, to: &d); appendLE32(subtype, to: &d)
        appendLE32(6, to: &d); appendLE32(3, to: &d)
        appendLE32(92, to: &d)
        appendLE32(0, to: &d); appendLE32(0, to: &d)
        appendLE32(0x0d, to: &d); appendLE32(52, to: &d); appendLE32(24, to: &d)
        appendLE32(0, to: &d); appendLE32(0x00010203, to: &d); appendLE32(0x00010000, to: &d)
        d.append(Data("com.example.plugin.dylib\0".utf8)); while d.count < 84 { d.append(0) }
        appendLE32(0x1b, to: &d); appendLE32(24, to: &d)
        d.append(contentsOf: (0..<16).map(UInt8.init))
        appendLE32(0x1d, to: &d); appendLE32(16, to: &d); appendLE32(0, to: &d); appendLE32(0, to: &d)
        return d
    }
    private func appendLE32(_ value: UInt32, to data: inout Data) {
        for shift in [0, 8, 16, 24] { data.append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }
    private func appendBE32(_ value: UInt32, to data: inout Data) {
        for shift in [24, 16, 8, 0] { data.append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }
}
