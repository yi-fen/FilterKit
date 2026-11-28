import Foundation

/// One local event stream with two deliberately separate projections:
/// developer JSONL (structured, privacy-redacted) and user activity JSONL (minimal).
/// Logging is best-effort, bounded, asynchronous, and never initiates inventory work.
enum RuntimeEventLogger {
    enum Level: String, Codable {
        case trace = "TRACE", debug = "DEBUG", info = "INFO", warning = "WARN", error = "ERROR", fatal = "FATAL"
    }

    struct Event: Codable, Identifiable {
        let timestamp: String
        let observedTimestamp: String
        let sessionID: String
        let traceID: String?
        let level: Level
        let severityNumber: Int
        let module: String
        let instrumentationScope: String
        let eventName: String
        let message: String
        let body: String
        let resource: [String: String]
        let attributes: [String: String]
        let activityTitle: String?
        let activityDetail: String?
        var id: String { "\(timestamp)-\(eventName)-\(traceID ?? "")" }
        var isUserVisible: Bool { activityTitle != nil }
    }

    /// User-facing history intentionally excludes session IDs, trace IDs, module names,
    /// arbitrary attributes, paths, bundle identifiers, hashes, and peer credentials.
    struct ActivityRecord: Codable, Identifiable {
        let timestamp: String
        let level: Level
        let eventName: String
        let activityTitle: String
        let activityDetail: String
        var id: String { "\(timestamp)-\(eventName)" }
    }

    private static let queue = DispatchQueue(label: "cn.yfen.filterkit.runtime-events", qos: .utility)
    private static let folder = "FilterKit/Logs"
    private static let developerFile = "runtime.jsonl"
    private static let developerPreviousFile = "runtime.previous.jsonl"
    private static let activityFile = "activity.jsonl"
    private static let activityPreviousFile = "activity.previous.jsonl"
    private static let maxFileBytes = 1_048_576
    private static let maxActivityBytes = 262_144
    private static let currentSessionKey = "cn.yfen.filterkit.runtime.current-session"
    private static let sessionID = UUID().uuidString.lowercased()
    private static let sensitiveAttributeFragments = ["token", "secret", "password", "authorization", "cookie", "cdhash", "path", "jbroot", "home_directory", "username", "provisioning_profile", "private_key"]

    static var logsDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folder, isDirectory: true)
    }
    static var developerLogURL: URL? { logsDirectoryURL?.appendingPathComponent(developerFile) }
    static var activityLogURL: URL? { logsDirectoryURL?.appendingPathComponent(activityFile) }

    static func startSession() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: currentSessionKey)
        if let previous, !previous.isEmpty {
            record(level: .warning, module: "AppLifecycle", event: "app.lifecycle.previous_session_unconfirmed",
                   message: "Previous app session ended without a recorded clean-shutdown marker.",
                   attributes: ["previous_session_id": previous, "classification": "suspected_abnormal_termination"],
                   activityTitle: "activity.previous_session_unconfirmed", activityDetail: "The previous session ended without a confirmed clean-shutdown marker; this does not prove a crash.")
        }
        defaults.set(sessionID, forKey: currentSessionKey)
        record(level: .info, module: "AppLifecycle", event: "app.lifecycle.launch.completed",
               message: "Application session started.", attributes: ["session_id": sessionID])
    }

    static func recordScenePhase(_ phase: String) {
        record(level: .info, module: "AppLifecycle", event: "app.lifecycle.scene.\(safeToken(phase))",
               message: "Application scene changed state.", attributes: ["scene_phase": safeToken(phase)])
    }

    /// Call only when the app has a positively confirmed clean shutdown path.
    /// iOS does not guarantee a termination callback, so absence is only a suspicion.
    static func markCleanTermination() {
        UserDefaults.standard.removeObject(forKey: currentSessionKey)
        record(level: .info, module: "AppLifecycle", event: "app.lifecycle.termination.clean",
               message: "Application recorded a clean termination.")
    }

    static func record(level: Level, module: String, event: String, message: String,
                       traceID: String? = nil, attributes: [String: String] = [:],
                       activityTitle: String? = nil, activityDetail: String? = nil) {
        let now = timestamp(Date())
        let item = Event(timestamp: now, observedTimestamp: now, sessionID: sessionID,
                         traceID: traceID.map { String($0.prefix(96)) }, level: level,
                         severityNumber: severity(level), module: safeToken(module),
                         instrumentationScope: safeToken(module), eventName: safeToken(event),
                         message: redactText(message), body: redactText(message),
                         resource: runtimeResource(),
                         attributes: redactAttributes(attributes),
                         activityTitle: activityTitle.map(safeLocalizationKey),
                         activityDetail: activityDetail.map(safeActivityDetail))
        queue.async { persist(item) }
    }

    enum OperationOutcome: String { case completed, failed, unknown, blocked }

    /// Record only after the underlying operation returns an authoritative result.
    static func recordPluginOperation(_ operation: String, succeeded: Bool, pluginID: String? = nil,
                                      detail: String? = nil, traceID: String? = nil) {
        recordPluginOperation(operation, outcome: succeeded ? .completed : .failed,
                              pluginID: pluginID, detail: detail, traceID: traceID)
    }

    static func recordPluginOperation(_ operation: String, outcome: OperationOutcome,
                                      pluginID: String? = nil, detail: String? = nil,
                                      traceID: String? = nil) {
        let allowedOperations: Set<String> = ["import", "activation", "association", "uninstall"]
        let safeOperation = allowedOperations.contains(operation) ? operation : "other"
        var attributes = ["operation": safeOperation, "outcome": outcome.rawValue]
        if let pluginID { attributes["plugin_id"] = String(pluginID.prefix(128)) }
        let level: Level = outcome == .completed ? .info : (outcome == .blocked ? .warning : .error)
        let titleKey = "activity.plugin_operation.\(safeOperation).\(outcome.rawValue)"
        let message = detail ?? "Plugin \(safeOperation) operation \(outcome.rawValue)."
        record(level: level, module: "PluginOperation", event: "plugin.\(safeOperation).\(outcome.rawValue)",
               message: message, traceID: traceID, attributes: attributes,
               activityTitle: titleKey, activityDetail: "")
    }

    static func recordLegacyDiagnostic(_ message: String) {
        record(level: .info, module: "Diagnostics", event: "diagnostics.performance.snapshot",
               message: message, attributes: ["format": "legacy_key_value"])
    }

    static func recentActivity(limit: Int = 300) -> [ActivityRecord] {
        queue.sync {
            guard let directory = logsDirectoryURL else { return [] }
            let urls = [directory.appendingPathComponent(activityPreviousFile), directory.appendingPathComponent(activityFile)]
            let decoder = JSONDecoder()
            var records: [ActivityRecord] = []
            for url in urls {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") {
                    guard let data = String(line).data(using: .utf8) else { continue }
                    if let item = try? decoder.decode(ActivityRecord.self, from: data) { records.append(item); continue }
                    // One-time compatibility with activity.jsonl written by earlier builds.
                    if let legacy = try? decoder.decode(Event.self, from: data), let title = legacy.activityTitle {
                        records.append(ActivityRecord(timestamp: legacy.timestamp, level: legacy.level,
                            eventName: legacy.eventName, activityTitle: safeLocalizationKey(title),
                            activityDetail: safeActivityDetail(legacy.activityDetail ?? "")))
                    }
                }
            }
            return Array(records.suffix(max(0, limit)).reversed())
        }
    }

    static func developerLogText() -> String {
        queue.sync {
            guard let directory = logsDirectoryURL else { return "" }
            return [developerPreviousFile, developerFile].compactMap {
                try? String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)
            }.joined(separator: "\n")
        }
    }

    static func developerLogExportURL() -> URL? {
        queue.sync {
            guard let directory = logsDirectoryURL else { return nil }
            let text = [developerPreviousFile, developerFile].compactMap {
                try? String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)
            }.joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("FilterKit-Diagnostics", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
                let url = exportDirectory.appendingPathComponent("FilterKit-Developer-Logs-\(Int(Date().timeIntervalSince1970)).jsonl")
                let header = "# FilterKit developer diagnostics; privacy-redacted; app-local logs only. Helper root audit is not included.\n"
                try (header + text).data(using: .utf8)?.write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                return url
            } catch { return nil }
        }
    }

    static func developerLogByteCount() -> Int {
        queue.sync {
            guard let directory = logsDirectoryURL else { return 0 }
            return [developerPreviousFile, developerFile].reduce(0) { total, name in
                let size = (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.size] as? NSNumber)?.intValue ?? 0
                return total + size
            }
        }
    }

    static func clearActivity() {
        queue.sync {
            guard let directory = logsDirectoryURL else { return }
            [activityFile, activityPreviousFile].forEach { try? FileManager.default.removeItem(at: directory.appendingPathComponent($0)) }
        }
    }

    static func clearDeveloperLogs() {
        queue.sync {
            guard let directory = logsDirectoryURL else { return }
            [developerFile, developerPreviousFile].forEach { try? FileManager.default.removeItem(at: directory.appendingPathComponent($0)) }
        }
    }

    private static func persist(_ event: Event) {
        guard let directory = logsDirectoryURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var encoded = try encoder.encode(event); encoded.append(0x0A)
            try append(encoded, to: directory.appendingPathComponent(developerFile), maximumBytes: maxFileBytes,
                       previousName: developerPreviousFile, directory: directory)
            if let title = event.activityTitle {
                let activity = ActivityRecord(timestamp: event.timestamp, level: event.level,
                    eventName: event.eventName, activityTitle: title,
                    activityDetail: safeActivityDetail(event.activityDetail ?? ""))
                var activityData = try encoder.encode(activity); activityData.append(0x0A)
                try append(activityData, to: directory.appendingPathComponent(activityFile), maximumBytes: maxActivityBytes,
                           previousName: activityPreviousFile, directory: directory)
            }
        } catch { /* Logging must never affect FilterKit behavior. */ }
    }

    private static func append(_ data: Data, to file: URL, maximumBytes: Int,
                               previousName: String?, directory: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + data.count > maximumBytes {
            if let previousName {
                let previous = directory.appendingPathComponent(previousName)
                try? FileManager.default.removeItem(at: previous)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.moveItem(at: file, to: previous) }
            } else { try? FileManager.default.removeItem(at: file) }
        }
        if FileManager.default.fileExists(atPath: file.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadCorruptFile) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd()
            try handle.write(contentsOf: data); try handle.close()
        } else {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private static func runtimeResource() -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        var resource = [
            "service.name": "FilterKit",
            "service.namespace": "cn.yfen",
            "os.name": "iOS",
            "os.version": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        if let version = info["CFBundleShortVersionString"] as? String { resource["service.version"] = version }
        if let build = info["CFBundleVersion"] as? String { resource["service.build"] = build }
        return resource
    }

    private static func severity(_ level: Level) -> Int {
        switch level { case .trace: return 1; case .debug: return 5; case .info: return 9; case .warning: return 13; case .error: return 17; case .fatal: return 21 }
    }
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private static func safeToken(_ value: String) -> String {
        let filtered = value.unicodeScalars.filter { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-" )).contains($0) }
        return String(String.UnicodeScalarView(filtered).prefix(96))
    }
    private static func safeLocalizationKey(_ value: String) -> String { String(value.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }.prefix(128)) }
    private static func safeActivityDetail(_ value: String) -> String {
        var safe = value
        let redactions: [(String, String)] = [
            (#"(?<![A-Za-z0-9])/(?:private/)?(?:var|Users|Library|Applications|System|etc|tmp)/[^\s,;]+"#, "[path hidden]"),
            (#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[email hidden]"),
            (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#, "[identifier hidden]"),
            (#"\b[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+){2,}\b"#, "[app identifier hidden]"),
            (#"\b[0-9a-fA-F]{32,}\b"#, "[hash hidden]")
        ]
        for (pattern, replacement) in redactions {
            safe = safe.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return String(safe.replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression).prefix(180))
    }
    private static func redactText(_ value: String) -> String {
        let noPaths = value.replacingOccurrences(of: #"(?<![A-Za-z0-9])/(?:private/)?(?:var|Users|Library|Applications|System|etc|tmp)/[^\s,;]+"#, with: "[path redacted]", options: .regularExpression)
        return String(noPaths.prefix(1024))
    }
    private static func redactAttributes(_ attributes: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in attributes.prefix(64) {
            let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
            if sensitiveAttributeFragments.contains(where: { normalized.contains($0) }) {
                result[key] = "[redacted]"
            } else {
                result[String(key.prefix(96))] = redactText(value)
            }
        }
        return result
    }
}
