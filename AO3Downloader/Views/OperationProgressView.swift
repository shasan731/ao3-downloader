import SwiftUI

struct OperationProgressView: View {
    let operation: ActiveOperation
    let canCancel: Bool
    let onCancel: () -> Void

    var body: some View {
        Section(operation.kind == .analysis ? "Analysis Progress" : "Download Progress") {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(operation.stage.rawValue).font(.headline)
                    if let title = operation.currentTitle { Text(title).lineLimit(1).truncationMode(.middle) }
                    Text(operation.detail).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                if canCancel { Button("Cancel", role: .destructive, action: onCancel) }
            }
            if let total = operation.totalCount, total > 0 {
                ProgressView(value: Double(min(operation.completedCount, total)), total: Double(total))
                Text("\(operation.completedCount) of \(total)").font(.caption).foregroundStyle(.secondary)
            } else if canCancel {
                ProgressView()
            }
            if canCancel {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Elapsed: \(elapsed(from: operation.startedAt, to: context.date))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Duration: \(elapsed(from: operation.startedAt, to: .now))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
