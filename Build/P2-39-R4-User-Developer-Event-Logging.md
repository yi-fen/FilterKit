# P2-39-R4 — User Activity & Developer Runtime Event Logging

## Implemented
- Added one `RuntimeEventLogger` event source and two local JSONL projections.
- Developer stream: `Library/Application Support/FilterKit/Logs/runtime.jsonl`, with bounded rotation to `runtime.previous.jsonl`.
- User stream: `activity.jsonl`, capped independently; displayed in Settings > Activity History.
- Event fields include ISO-8601 timestamps, session/trace identifiers, level and OpenTelemetry severity number, resource, instrumentation scope, event name, body/message, and attributes.
- App launch and scene lifecycle events are recorded.
- Plugin inventory completion/failure events are recorded after the actual scan result is known.
- A reusable `recordPluginOperation` API is provided for import, activation, association, and uninstall operation boundaries.
- Removed the developer diagnostics/log display route from Settings. Developer logs are file-only; the Activity History UI is user-facing.
- Existing P2-39 key-value summaries are preserved as structured developer events through a compatibility facade.

## Important limitations
- Import/uninstall/activation flows are not currently wired end-to-end in this source snapshot. The event API is ready, but no success/failure activity is fabricated.
- iOS does not guarantee a termination callback. A persisted session marker can only identify an unconfirmed previous session, not prove a crash. System `.ips` reports are not read from the app sandbox.
- Helper attestation outcome events remain represented by existing counters/summaries; no new Helper behavior or IPC was added.
- No inventory, association, Helper, release-gate, or plugin mutation behavior was changed.

## Validation
- Swift parser: all App, Sources, and UnitTests Swift files.
- Host typecheck: RuntimeEventLogger.swift + RuntimeDiagnosticsStore.swift.
- XCTest execution and Xcode/iOS build require an Apple toolchain and were not run in this environment.
