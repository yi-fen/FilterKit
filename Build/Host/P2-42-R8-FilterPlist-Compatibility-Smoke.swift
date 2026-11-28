
import Foundation

func plist(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let canonical = PluginFilterConfiguration.parse(try plist(["Filter": [
    "Bundles": ["com.example.reader"], "Executables": [String](), "Classes": ["ReaderClass"]
]]))
require(canonical.parseState == .valid && canonical.bundles == ["com.example.reader"], "canonical nested filter")
let lowerAndScalar = PluginFilterConfiguration.parse(try plist(["filter": [
    "bundles": "com.example.reader", "executables": "Reader"
]]))
require(lowerAndScalar.parseState == .valid && lowerAndScalar.bundles == ["com.example.reader"] &&
        lowerAndScalar.executables == ["Reader"], "case-insensitive keys and scalar target")
let explicitEmpty = PluginFilterConfiguration.parse(try plist(["Filter": [
    "Bundles": [String](), "Executables": [String](), "Classes": ["Standalone"]
]]))
require(explicitEmpty.parseState == .valid && explicitEmpty.bundles.isEmpty &&
        explicitEmpty.executables.isEmpty, "explicit empty targets")
let missingTargets = PluginFilterConfiguration.parse(try plist(["Filter": [
    "Classes": ["ClassOnly"], "Mode": "Any"
]]))
require(missingTargets.parseState == .partial &&
        missingTargets.warnings.contains("plugin_filter.load_target_fields_missing"),
        "missing target fields must not imply standalone")
let wrongType = PluginFilterConfiguration.parse(try plist(["Bundles": 42, "Executables": [String]()] ))
require(wrongType.parseState == .partial && wrongType.bundles.isEmpty, "malformed target type")
let mixed = PluginFilterConfiguration.parse(try plist(["Filter": [
    "Bundles": ["com.example.reader", 7], "Executables": [String]()
]]))
require(mixed.parseState == .partial && mixed.bundles == ["com.example.reader"], "retain valid entries but flag malformed entries")
let duplicateKeys = PluginFilterConfiguration.parse(try plist([
    "Bundles": ["com.example.one"], "bundles": ["com.example.two"], "Executables": [String]()
]))
require(duplicateKeys.parseState == .partial &&
        duplicateKeys.warnings.contains("plugin_filter.duplicate_key_bundles"),
        "case-variant duplicate keys must be rejected as ambiguous")
print("P2-42-R8 Filter.plist compatibility smoke: PASS (7 cases)")
