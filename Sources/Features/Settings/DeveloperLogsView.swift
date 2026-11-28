import SwiftUI
import UIKit

struct DeveloperLogsView: View {
    @State private var exportFile: ShareableDiagnosticLog?
    @State private var showingClearConfirmation = false
    @State private var byteCount = RuntimeEventLogger.developerLogByteCount()
    @State private var preview = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Label("logs.developer.size", systemImage: "doc.text")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                        .foregroundColor(.secondary).monospacedDigit()
                }
                Text("logs.developer.privacy_note")
                    .font(.footnote).foregroundColor(.secondary)
                Text("logs.developer.helper_note")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section {
                Button {
                    if let url = RuntimeEventLogger.developerLogExportURL() { exportFile = ShareableDiagnosticLog(url: url) }
                } label: {
                    Label("logs.developer.export", systemImage: "square.and.arrow.up")
                }
                .disabled(byteCount == 0)
                Button("logs.developer.clear", role: .destructive) { showingClearConfirmation = true }
                    .disabled(byteCount == 0)
            }
            Section(header: Text("logs.developer.preview")) {
                if preview.isEmpty {
                    Text("logs.developer.empty").foregroundColor(.secondary)
                } else {
                    Text(preview).font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("logs.developer.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $exportFile) { item in
            DiagnosticLogShareSheet(activityItems: [item.url])
        }
        .confirmationDialog("logs.developer.clear_confirm", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("logs.developer.clear", role: .destructive) {
                RuntimeEventLogger.clearDeveloperLogs()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func reload() {
        byteCount = RuntimeEventLogger.developerLogByteCount()
        let lines = RuntimeEventLogger.developerLogText().split(separator: "\n")
        preview = lines.suffix(40).joined(separator: "\n")
    }
}

private struct ShareableDiagnosticLog: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct DiagnosticLogShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
