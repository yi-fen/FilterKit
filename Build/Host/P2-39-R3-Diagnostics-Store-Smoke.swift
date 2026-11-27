import Foundation

@main
struct P239R3DiagnosticsStoreSmoke {
    static func main() {
        RuntimeDiagnosticsStore.clear()
        RuntimeDiagnosticsStore.append("[Smoke] local_log_round_trip=true")
        let output = RuntimeDiagnosticsStore.exportText()
        precondition(output.contains("local_log_round_trip=true"))
        RuntimeDiagnosticsStore.clear()
        precondition(!RuntimeDiagnosticsStore.exportText().contains("local_log_round_trip=true"))
        print("P2-39-R3 diagnostics store smoke: PASS")
    }
}
