import SwiftUI

struct ActivityHistoryView: View {
    @State private var records: [RuntimeEventLogger.ActivityRecord] = []
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if records.isEmpty {
                Text("activity.empty")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LocalizedStringKey(record.activityTitle.isEmpty ? record.eventName : record.activityTitle))
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(record.level.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundColor(record.level == .error || record.level == .fatal ? .red : .secondary)
                        }
                        if !record.activityDetail.isEmpty {
                            Text(record.activityDetail).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(record.timestamp)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("activity.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("activity.clear") { showingClearConfirmation = true }
                    .disabled(records.isEmpty)
            }
        }
        .confirmationDialog("activity.clear_confirm", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("activity.clear", role: .destructive) {
                RuntimeEventLogger.clearActivity()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: reload)
    }

    private func reload() { records = RuntimeEventLogger.recentActivity() }
}
