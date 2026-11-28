#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
logger = (ROOT / "Sources/Environment/RuntimeEventLogger.swift").read_text()
activity = (ROOT / "Sources/Features/Settings/ActivityHistoryView.swift").read_text()
dev_view = (ROOT / "Sources/Features/Settings/DeveloperLogsView.swift").read_text()
settings = (ROOT / "Sources/Features/Settings/SettingsView.swift").read_text()
helper_sink = (ROOT / "Sources/Environment/Helper/Runtime/HelperAuditFileSink.swift").read_text()
collector = (ROOT / "Build/scripts/p245_r4_3_collect_helper_audit.sh").read_text()
smoke = (ROOT / "Build/Host/RuntimeEventLoggerSmoke.swift").read_text()
activation_store = (ROOT / "Sources/Environment/Deployment/AppPluginActivationOperationStore.swift").read_text()
plugins_view = (ROOT / "Sources/Features/Plugins/PluginsView.swift").read_text()
checks = [
    ("distinct minimal ActivityRecord", "struct ActivityRecord: Codable, Identifiable" in logger and "sessionID" not in logger.split("struct ActivityRecord",1)[1].split("private static let queue",1)[0]),
    ("developer JSONL remains structured", "developerFile = \"runtime.jsonl\"" in logger and "severityNumber" in logger),
    ("activity JSONL separate", "activityFile = \"activity.jsonl\"" in logger and "ActivityRecord(timestamp:" in logger),
    ("sensitive attribute redaction", "sensitiveAttributeFragments" in logger and "[redacted]" in logger),
    ("absolute path redaction", "[path redacted]" in logger and "[path hidden]" in logger),
    ("email and UUID redaction in user activity", "[email hidden]" in logger and "[identifier hidden]" in logger),
    ("bundle identifier and hash redaction in user activity", "[app identifier hidden]" in logger and "[hash hidden]" in logger),
    ("bounded developer log", "maxFileBytes = 1_048_576" in logger and "developerPreviousFile" in logger),
    ("bounded user activity log", "maxActivityBytes = 262_144" in logger and "activityPreviousFile" in logger),
    ("legacy activity compatibility", "One-time compatibility" in logger),
    ("asynchronous best-effort persistence", "queue.async { persist(item) }" in logger and "Logging must never affect FilterKit behavior" in logger),
    ("diagnostic export", "developerLogExportURL()" in logger and "privacy-redacted" in logger),
    ("developer log size and clear", "developerLogByteCount()" in logger and "clearDeveloperLogs()" in logger),
    ("activity view uses minimal record", "RuntimeEventLogger.ActivityRecord" in activity),
    ("developer diagnostics view", "DeveloperLogsView" in settings and "Export Developer Logs" not in settings),
    ("developer export uses share sheet", "UIActivityViewController" in dev_view and "developerLogExportURL" in dev_view),
    ("helper audit remains root-only", "info.st_uid == 0" in helper_sink and "0o600" in helper_sink),
    ("helper collector read-only source", "cp \"$SOURCE\"" in collector and "chmod 700 \"$OUTPUT_REAL\"" in collector),
    ("helper collector rejects symlinks", "[ ! -L \"$SOURCE\" ]" in collector and "[ ! -L \"$JBROOT\" ]" in collector and "unsafe Helper audit directory component" in collector),
    ("helper collector validates root group and link count", "GROUP=$(stat -f '%g'" in collector and "LINKS=$(stat -f '%l'" in collector),
    ("helper collector output outside JBROOT", "output must be outside JBROOT" in collector),
    ("runtime privacy smoke coverage", "[path redacted]" in smoke and "[path hidden]" in smoke and "com.example.test" in smoke),
    ("activation logs only authoritative result", "outcome: .completed" in activation_store and "outcome: .unknown" in activation_store and "outcome: .blocked" in activation_store),
    ("association logs after validated Helper receipt", "receipt.requestID.uuidString" in plugins_view and "recordPluginOperation(\"association\"" in plugins_view),
    ("runtime platform/version resource", "os.version" in logger and "service.version" in logger and "service.build" in logger),
]
failed = 0
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'} {name}")
    failed += not ok
print(f"R4.3_LOGGING_AUDIT={len(checks)-failed}/{len(checks)}")
raise SystemExit(1 if failed else 0)
