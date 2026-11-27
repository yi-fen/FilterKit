import Foundation

protocol PluginDiscoveryProvider { func scanPlugins() async throws -> PluginScanResult }

@main
struct P233PluginIdentitySmoke {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("p233-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let dylib = try makeSignedMachO()
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Filter": [
            "Bundles": ["com.example.target"],
            "Executables": ["TargetExecutable", 7],
            "Classes": ["TargetClass"],
            "Mode": true
        ]], format: .xml, options: 0)
        try dylib.write(to: base.appendingPathComponent("Demo.dylib"))
        try plist.write(to: base.appendingPathComponent("Demo.plist"))

        let slices = try MachOMetadataReader().readSlices(data: dylib)
        try require(slices.count == 1, "single architecture slice")
        try require(slices[0].architecture == "arm64", "architecture extraction")
        try require(slices[0].codeSignatureState == "cdhash_extracted", "CDHash extraction")
        try require(slices[0].codeSignatureIdentifier == "com.example.test", "CodeDirectory identifier")
        try require(slices[0].codeSignatureTeamIdentifier == "ABCDE12345", "CodeDirectory team identifier")
        try require(slices[0].codeSignatureFlags == 0x10000, "CodeDirectory flags")
        try require(slices[0].codeSignaturePlatform == 2, "CodeDirectory platform")

        let parsed = PluginFilterConfiguration.parse(plist)
        try require(parsed.bundles == ["com.example.target"], "Bundles extraction")
        try require(parsed.executables.count == 2 && parsed.executables[0] == "TargetExecutable" && parsed.executables[1].contains("integer"), "Executables extraction including non-string preservation")
        try require(parsed.classes == ["TargetClass"], "Classes extraction")
        try require(parsed.modeDescription == "true", "Mode extraction")

        let assessment = PluginDirectoryAssessment(state: .resolved, selectedPath: base.path,
            candidates: [], warnings: [], isReadOnly: true)
        let scan = ReadOnlyPluginScanner().scan(assessment: assessment)
        guard let item = scan.plugins.first else { throw SmokeError.failed("scanner inventory") }
        try require(item.binaryKind == .machO, "scanner Mach-O classification")
        try require(item.machOArchitectures == ["arm64"], "scanner architecture projection")
        try require(item.machOCDHashes.count == 1, "scanner CDHash projection")
        try require(item.filterConfiguration?.executables.count == 2, "scanner Filter projection")
        try require(item.dylibSHA256 != nil && item.plistSHA256 != nil, "bounded file SHA-256 projection")
        try require(item.managementPermission?.canModify == false, "identity metadata does not grant mutation permission")

        print("P2-33 identity smoke: PASS (Mach-O architecture/CDHash/CodeDirectory metadata, Filter fields, inventory projection, read-only permission boundary)")
    }

    static func require(_ condition: Bool, _ name: String) throws {
        if !condition { throw SmokeError.failed(name) }
    }

    static func makeSignedMachO() throws -> Data {
        var d = Data([0xcf, 0xfa, 0xed, 0xfe])
        appendLE32(0x0100000c, &d); appendLE32(0, &d)
        appendLE32(6, &d); appendLE32(3, &d); appendLE32(92, &d); appendLE32(0, &d); appendLE32(0, &d)
        appendLE32(0x0d, &d); appendLE32(52, &d); appendLE32(24, &d)
        appendLE32(0, &d); appendLE32(0, &d); appendLE32(0x00010000, &d)
        d.append(Data(repeating: 0, count: 28))
        appendLE32(0x1b, &d); appendLE32(24, &d); d.append(contentsOf: (0..<16).map(UInt8.init))
        appendLE32(0x1d, &d); appendLE32(16, &d); appendLE32(124, &d); appendLE32(132, &d)
        appendBE32(0xFADE0CC0, &d); appendBE32(132, &d); appendBE32(1, &d)
        appendBE32(0, &d); appendBE32(20, &d)
        appendBE32(0xFADE0C02, &d); appendBE32(112, &d); appendBE32(0x00020200, &d)
        appendBE32(0x00010000, &d); appendBE32(0, &d); appendBE32(64, &d)
        appendBE32(0, &d); appendBE32(0, &d); appendBE32(0, &d)
        d.append(32); d.append(2); d.append(2); d.append(12)
        appendBE32(0, &d); appendBE32(0, &d); appendBE32(88, &d); appendBE32(0, &d)
        d.append(Data(repeating: 0, count: 8))
        d.append(Data("com.example.test\0".utf8)); d.append(Data(repeating: 0, count: 7))
        d.append(Data("ABCDE12345\0".utf8)); d.append(Data(repeating: 0, count: 13))
        return d
    }

    static func appendLE32(_ value: UInt32, _ data: inout Data) {
        for shift in [0, 8, 16, 24] { data.append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }
    static func appendBE32(_ value: UInt32, _ data: inout Data) {
        for shift in [24, 16, 8, 0] { data.append(UInt8((value >> UInt32(shift)) & 0xff)) }
    }
}

enum SmokeError: Error { case failed(String) }
