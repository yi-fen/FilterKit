import Foundation
import CoreFoundation

enum PluginFilterParseState: String, Codable, Equatable {
    case valid
    case partial
    case invalid
    case unavailable
}

/// Read-only projection of the ElleKit filter dictionary. Original plist bytes remain untouched.
struct PluginFilterConfiguration: Codable, Equatable {
    let parseState: PluginFilterParseState
    let containerKey: String
    let bundles: [String]
    let executables: [String]
    let classes: [String]
    /// Preserves the plist value as a display string; semantics are not inferred here.
    let modeDescription: String?
    let unknownKeys: [String]
    let warnings: [String]

    static func parse(_ data: Data) -> PluginFilterConfiguration {
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let root = object as? [String: Any] else {
                return invalid("plugin_filter.root_not_dictionary")
            }
            let filter: [String: Any]
            let containerKey: String
            if let rawFilter = root["Filter"] {
                guard let dictionary = rawFilter as? [String: Any] else {
                    return invalid("plugin_filter.filter_not_dictionary")
                }
                filter = dictionary
                containerKey = "Filter"
            } else {
                filter = root
                containerKey = "root"
            }

            var warnings: [String] = []
            func stringArray(_ key: String) -> [String] {
                guard let raw = filter[key] else { return [] }
                guard let values = raw as? [Any] else {
                    warnings.append("plugin_filter.\(key.lowercased())_not_array")
                    return []
                }
                let strings = values.map { value -> String in
                    if let string = value as? String { return string }
                    return displayPropertyListValue(value)
                }
                if values.contains(where: { !($0 is String) }) {
                    warnings.append("plugin_filter.\(key.lowercased())_contains_non_string")
                }
                return strings
            }
            let bundles = stringArray("Bundles")
            let executables = stringArray("Executables")
            let classes = stringArray("Classes")
            let mode: String?
            if let rawMode = filter["Mode"] {
                if let value = rawMode as? String { mode = value }
                else if let value = rawMode as? NSNumber {
                    mode = CFGetTypeID(value) == CFBooleanGetTypeID() ? (value.boolValue ? "true" : "false") : value.stringValue
                } else { mode = displayPropertyListValue(rawMode); warnings.append("plugin_filter.mode_unrecognized_type") }
            } else { mode = nil }
            let known: Set<String> = ["Bundles", "Executables", "Classes", "Mode"]
            let unknown = filter.keys.filter { !known.contains($0) }.sorted()
            return PluginFilterConfiguration(parseState: warnings.isEmpty ? .valid : .partial,
                containerKey: containerKey, bundles: bundles, executables: executables,
                classes: classes, modeDescription: mode, unknownKeys: unknown, warnings: warnings)
        } catch {
            return invalid("plugin_filter.plist_parse_failed")
        }
    }

    private static func displayPropertyListValue(_ value: Any) -> String {
        if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0),
           let text = String(data: data, encoding: .utf8) { return text }
        return String(describing: value)
    }

    private static func invalid(_ warning: String) -> PluginFilterConfiguration {
        PluginFilterConfiguration(parseState: .invalid, containerKey: "unknown", bundles: [],
            executables: [], classes: [], modeDescription: nil, unknownKeys: [], warnings: [warning])
    }
}
