import Foundation
import CoreFoundation

enum PluginFilterParseState: String, Codable, Equatable {
    case valid
    case partial
    case invalid
    case unavailable
}

/// Read-only projection of ElleKit's Filter dictionary. Original plist bytes remain untouched.
/// The parser accepts canonical and case-insensitive key spellings, plus either a single
/// string or an array for target fields. It never guesses semantics for unknown fields.
struct PluginFilterConfiguration: Codable, Equatable {
    let parseState: PluginFilterParseState
    let containerKey: String
    let bundles: [String]
    let executables: [String]
    let classes: [String]
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
            if let filterEntry = root.first(where: { $0.key.caseInsensitiveCompare("Filter") == .orderedSame }) {
                guard let dictionary = filterEntry.value as? [String: Any] else {
                    return invalid("plugin_filter.filter_not_dictionary")
                }
                filter = dictionary
                containerKey = filterEntry.key
            } else {
                filter = root
                containerKey = "root"
            }

            var warnings: [String] = []
            let normalizedKeyCounts = Dictionary(grouping: filter.keys, by: { $0.lowercased() })
            for (key, spellings) in normalizedKeyCounts where spellings.count > 1 {
                warnings.append("plugin_filter.duplicate_key_\(key)")
            }
            func entry(_ key: String) -> (String, Any)? {
                let matches = filter.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
                guard matches.count == 1, let match = matches.first else { return nil }
                return (match.key, match.value)
            }
            func stringArray(_ key: String) -> [String] {
                guard let (_, raw) = entry(key) else { return [] }
                if let string = raw as? String {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        warnings.append("plugin_filter.\\(key.lowercased())_empty_string")
                        return []
                    }
                    return [trimmed]
                }
                guard let values = raw as? [Any] else {
                    warnings.append("plugin_filter.\\(key.lowercased())_not_array_or_string")
                    return []
                }
                var result: [String] = []
                for value in values {
                    guard let string = value as? String else {
                        warnings.append("plugin_filter.\\(key.lowercased())_contains_non_string")
                        continue
                    }
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        warnings.append("plugin_filter.\\(key.lowercased())_contains_empty_string")
                    } else {
                        result.append(trimmed)
                    }
                }
                return result
            }

            let hasBundles = entry("Bundles") != nil
            let hasExecutables = entry("Executables") != nil
            // Without either target field, an empty parse is not proof of an independent
            // plugin. It may be a different/unsupported Filter.plist dialect.
            if !hasBundles && !hasExecutables {
                warnings.append("plugin_filter.load_target_fields_missing")
            }

            let bundles = stringArray("Bundles")
            let executables = stringArray("Executables")
            let classes = stringArray("Classes")
            let mode: String?
            if let (_, rawMode) = entry("Mode") {
                if let value = rawMode as? String { mode = value }
                else if let value = rawMode as? NSNumber {
                    mode = CFGetTypeID(value) == CFBooleanGetTypeID()
                        ? (value.boolValue ? "true" : "false") : value.stringValue
                } else {
                    mode = displayPropertyListValue(rawMode)
                    warnings.append("plugin_filter.mode_unrecognized_type")
                }
            } else { mode = nil }

            let known: Set<String> = ["bundles", "executables", "classes", "mode"]
            let unknown = filter.keys.filter { !known.contains($0.lowercased()) }.sorted()
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
