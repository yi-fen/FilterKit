import Foundation
@main struct RuntimeEventLoggerSmoke {
    static func main() {
        RuntimeEventLogger.clearDeveloperLogs()
        RuntimeEventLogger.clearActivity()
        RuntimeEventLogger.startSession()
        RuntimeEventLogger.recordPluginOperation("import", succeeded: true, pluginID: "com.example.test", detail: "Imported test plugin.")
        RuntimeEventLogger.recordPluginOperation("activation", outcome: .unknown, pluginID: "com.example.test", traceID: UUID().uuidString)
        RuntimeEventLogger.record(level: .error, module: "Smoke", event: "diagnostics.redaction.test",
            message: "Failure at /var/mobile/Library/FilterKit/private.json",
            attributes: ["socket_path": "/var/run/filterkit.sock", "reason": "permission_denied"],
            activityTitle: "activity.helper_status_failed", activityDetail: "Failed at /var/mobile/Library/FilterKit/private.json")
        let developer = RuntimeEventLogger.developerLogText()
        let activity = RuntimeEventLogger.recentActivity()
        let activityText = activity.map { "\($0.eventName) \($0.activityTitle) \($0.activityDetail)" }.joined(separator: "\n")
        precondition(developer.contains("plugin.import.completed"))
        precondition(developer.contains("severityNumber"))
        precondition(developer.contains("[redacted]"))
        precondition(developer.contains("[path redacted]"))
        precondition(!developer.contains("/var/mobile/Library/FilterKit/private.json"))
        precondition(activity.contains { $0.eventName == "plugin.import.completed" })
        precondition(activity.contains { $0.eventName == "plugin.activation.unknown" })
        precondition(!activityText.contains("com.example.test"))
        precondition(!activityText.contains("/var/mobile/Library"))
        precondition(activityText.contains("[path hidden]"))
        RuntimeEventLogger.clearDeveloperLogs()
        RuntimeEventLogger.clearActivity()
        print("runtime_event_logger_smoke=passed")
    }
}
