import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("FAIL: \(message)") }
    print("PASS: \(message)")
}

let generated = try PluginImportInspector.makeBaseFilterPlist(targetBundleIdentifier: "com.example.target")
let parsed = PluginFilterConfiguration.parse(generated)
expect(parsed.parseState == .valid, "generated plist parses")
expect(parsed.bundles == ["com.example.target"], "generated plist scopes to target app")
expect(parsed.executables.isEmpty && parsed.classes.isEmpty && parsed.modeDescription == nil,
       "generator does not invent unknown injection rules")
expect((try? PluginImportInspector.makeBaseFilterPlist(targetBundleIdentifier: "../bad")) == nil,
       "invalid bundle identifier rejected")

let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fk-p240-r1-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let dylib = root.appendingPathComponent("Demo.dylib")
// Minimal little-endian 64-bit Mach-O header for arm64, with no load commands.
let machO = Data([0xcf,0xfa,0xed,0xfe, 0x0c,0x00,0x00,0x01, 0x00,0x00,0x00,0x00,
                  0x02,0x00,0x00,0x00, 0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
                  0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00])
try machO.write(to: dylib)
let result = try PluginImportInspector().inspect(dylibURL: dylib, originalPlistURL: nil,
                                                  targetBundleIdentifier: "com.example.target")
expect(result.usesGeneratedPlist, "dylib-only import generates Filter.plist")
expect(result.architectures == ["arm64"], "Mach-O architecture extracted")
expect(result.generatedPlist != nil, "generated plist bytes returned for staging pipeline")
expect(result.dylibSHA256.count == 64, "dylib SHA-256 computed")

let supplied = root.appendingPathComponent("Filter.plist")
let suppliedBytes = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.target"], "Classes": ["DemoClass"], "VendorFlag": true]], format: .xml, options: 0)
try suppliedBytes.write(to: supplied)
let withOriginal = try PluginImportInspector().inspect(dylibURL: dylib, originalPlistURL: supplied,
                                                        targetBundleIdentifier: "com.example.target")
expect(!withOriginal.usesGeneratedPlist && withOriginal.generatedPlist == nil,
       "original plist is not replaced by generated configuration")
expect(withOriginal.originalPlistSHA256 == SHA256Digest.hex(suppliedBytes),
       "original plist bytes are fingerprinted unchanged")
print("P2-40-R1 import inspection smoke: PASS")
