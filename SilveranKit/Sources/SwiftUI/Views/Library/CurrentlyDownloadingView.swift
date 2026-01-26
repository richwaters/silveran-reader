import SilveranKitCommon
import SwiftUI

struct CurrentlyDownloadingView: View {
    @State private var downloads: [DownloadRecord] = []
    @State private var observerId: UUID?

    var body: some View {
        List {
            if downloads.isEmpty {
                ContentUnavailableView(
                    "No Active Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloads that are in progress, paused, or failed will appear here.")
                )
            } else {
                ForEach(downloads) { record in
                    DownloadRecordRow(record: record)
                }
            }
        }
        .navigationTitle("Currently Downloading")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            downloads = await DownloadManager.shared.incompleteDownloads

            observerId = await DownloadManager.shared.addObserver { records in
                downloads = records
                    .filter { $0.isIncomplete }
                    .sorted { $0.createdAt < $1.createdAt }
            }
        }
    }
}

private struct DownloadRecordRow: View {
    let record: DownloadRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.bookTitle)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(categoryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(stateLabel)
                    .font(.caption)
                    .foregroundStyle(stateLabelColor)
            }

            if showProgressBar {
                ProgressView(value: record.progressFraction)
                    .tint(progressTint)
            }

            HStack {
                if record.expectedBytes != nil || record.receivedBytes > 0 {
                    Text(formatBytes(record.receivedBytes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let expected = record.expectedBytes {
                        Text("of \(formatBytes(expected))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if canResume {
                    Button {
                        Task {
                            await DownloadManager.shared.resumeDownload(
                                for: record.bookId,
                                category: record.category
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: resumeIcon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(resumeLabel)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await DownloadManager.shared.cancelDownload(
                        for: record.bookId,
                        category: record.category
                    )
                }
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
        }
    }

    private var canResume: Bool {
        switch record.state {
        case .paused, .failed: true
        default: false
        }
    }

    private var resumeLabel: String {
        if case .failed = record.state { return "Retry" }
        return "Resume"
    }

    private var resumeIcon: String {
        if case .failed = record.state { return "arrow.clockwise" }
        return "play.fill"
    }

    private var categoryLabel: String {
        switch record.category {
        case .ebook: "Ebook"
        case .audio: "Audiobook"
        case .synced: "Readaloud"
        }
    }

    private var stateLabel: String {
        switch record.state {
        case .queued: "Queued"
        case .downloading(let progress):
            "Downloading \(Int(progress * 100))%"
        case .paused: "Paused"
        case .failed(let error, _): "Failed: \(error)"
        case .importing: "Importing..."
        case .completed: "Completed"
        }
    }

    private var stateLabelColor: Color {
        switch record.state {
        case .failed: .red
        case .paused: .orange
        case .completed: .green
        default: .secondary
        }
    }

    private var showProgressBar: Bool {
        switch record.state {
        case .downloading, .importing, .queued: true
        case .paused(let hasResume): hasResume
        case .failed(_, let hasResume): hasResume
        case .completed: false
        }
    }

    private var progressTint: Color {
        switch record.state {
        case .paused: .orange
        case .failed: .red
        default: .accentColor
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
