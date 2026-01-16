#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ServerMediaManagementView: View {
    let item: BookMetadata
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaViewModel.self) private var mediaViewModel

    @State private var isUploading = false
    @State private var uploadProgress: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isStartingAlignment = false
    @State private var isCancelingAlignment = false
    @State private var errorMessage: String?

    public init(item: BookMetadata) {
        self.item = item
    }

    private var isValidServerBook: Bool {
        mediaViewModel.isServerBook(item.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isValidServerBook {
                headerView
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        localMediaSection
                        serverMediaSection
                        actionsSection
                    }
                    .padding(20)
                }
                if let error = errorMessage {
                    Divider()
                    errorView(message: error)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("This book is not from the server")
                        .font(.headline)
                    Text("Server media management is only available for books synced from Storyteller.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            }
            Divider()
            footerView
        }
        .frame(width: 500, height: 500)
        .confirmationDialog(
            "Delete Book from Server?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteBook() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the book and all its media from the server and remove any local downloads. This cannot be undone.")
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            coverImage
                .frame(width: 60, height: 90)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if let authors = item.authors, !authors.isEmpty {
                    Text(authors.compactMap(\.name).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var localMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Downloads")
                .font(.headline)

            mediaStatusRow(
                label: "Ebook",
                icon: "book.fill",
                isAvailable: mediaViewModel.isCategoryDownloaded(.ebook, for: item)
            )
            mediaStatusRow(
                label: "Audiobook",
                icon: "headphones",
                isAvailable: mediaViewModel.isCategoryDownloaded(.audio, for: item)
            )
            mediaStatusRow(
                label: "Readaloud",
                icon: "text.book.closed.fill",
                isAvailable: mediaViewModel.isCategoryDownloaded(.synced, for: item)
            )
        }
    }

    private var serverMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server Media")
                .font(.headline)

            serverMediaRow(
                label: "Ebook",
                icon: "book.fill",
                asset: item.ebook,
                readaloud: nil
            )
            serverMediaRow(
                label: "Audiobook",
                icon: "headphones",
                asset: item.audiobook,
                readaloud: nil
            )
            serverReadaloudRow()
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                uploadButton(label: "Add/Replace Ebook", format: .ebook, types: [.epub])
                uploadButton(label: "Add/Replace Audiobook", format: .audiobook, types: audioTypes)
            }

            if canStartAlignment {
                Button {
                    Task { await startAlignment(restart: false) }
                } label: {
                    HStack {
                        if isStartingAlignment {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Start Alignment")
                    }
                }
                .disabled(isStartingAlignment || isUploading)
            }

            if canRestartAlignment {
                Button {
                    Task { await startAlignment(restart: true) }
                } label: {
                    HStack {
                        if isStartingAlignment {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Restart Alignment")
                    }
                }
                .disabled(isStartingAlignment || isUploading)
            }

            if isAlignmentInProgress {
                Button {
                    Task { await cancelAlignment() }
                } label: {
                    HStack {
                        if isCancelingAlignment {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Cancel Alignment")
                    }
                }
                .disabled(isCancelingAlignment || isUploading)
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Label("Delete Book from Server", systemImage: "trash")
                }
            }
            .disabled(isDeleting || isUploading)
        }
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
        }
    }

    private func mediaStatusRow(label: String, icon: String, isAvailable: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(label)
            Spacer()
            if isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                Text("Not downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func serverMediaRow(
        label: String,
        icon: String,
        asset: BookAsset?,
        readaloud: BookReadaloud?
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(label)
            Spacer()
            if let asset {
                if asset.isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Missing on server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                Text("Not on server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func serverReadaloudRow() -> some View {
        HStack {
            Image(systemName: "text.book.closed.fill")
                .frame(width: 20)
            Text("Readaloud")
            Spacer()
            if let readaloud = item.readaloud {
                if readaloud.isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Missing on server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let status = readaloud.status?.uppercased() {
                    switch status {
                    case "ALIGNED":
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case "PROCESSING":
                        ProgressView()
                            .scaleEffect(0.7)
                        if let stage = readaloud.currentStage, let progress = readaloud.stageProgress {
                            Text("\(stage): \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Processing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case "QUEUED":
                        Image(systemName: "clock")
                            .foregroundStyle(.orange)
                        if let pos = readaloud.queuePosition {
                            Text("Queued (#\(pos))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Queued")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case "ERROR", "STOPPED":
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(status.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    default:
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Unknown status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                Text("Not on server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uploadButton(label: String, format: StorytellerBookFormat, types: [UTType]) -> some View {
        Button {
            selectAndUploadFile(format: format, types: types)
        } label: {
            HStack {
                if isUploading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text(label)
            }
        }
        .disabled(isUploading || isDeleting)
    }

    private var audioTypes: [UTType] {
        [
            UTType(filenameExtension: "m4b")!,
            UTType(filenameExtension: "m4a")!,
            .mp3,
            UTType(filenameExtension: "flac"),
            .zip
        ].compactMap { $0 }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let image = mediaViewModel.coverImage(for: item, variant: .standard) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var canStartAlignment: Bool {
        let hasEbook = item.ebook != nil && item.ebook?.isMissing != true
        let hasAudiobook = item.audiobook != nil && item.audiobook?.isMissing != true
        let noReadaloud = item.readaloud == nil
        return hasEbook && hasAudiobook && noReadaloud
    }

    private var canRestartAlignment: Bool {
        guard let readaloud = item.readaloud else { return false }
        let status = readaloud.status?.uppercased() ?? ""
        return status == "ERROR" || status == "STOPPED"
    }

    private var isAlignmentInProgress: Bool {
        guard let readaloud = item.readaloud else { return false }
        let status = readaloud.status?.uppercased() ?? ""
        return status == "PROCESSING" || status == "QUEUED"
    }

    private func selectAndUploadFile(format: StorytellerBookFormat, types: [UTType]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select file to upload"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await uploadFile(url: url, format: format)
        }
    }

    private func uploadFile(url: URL, format: StorytellerBookFormat) async {
        isUploading = true
        uploadProgress = "Reading file..."
        errorMessage = nil

        do {
            let data = try Data(contentsOf: url)
            let asset = StorytellerUploadAsset(
                format: format,
                filename: url.lastPathComponent,
                data: data
            )

            uploadProgress = "Uploading..."
            let success = await StorytellerActor.shared.uploadBookAssets(
                bookUUID: item.uuid,
                ebook: format == .ebook ? asset : nil,
                audiobook: format == .audiobook ? asset : nil,
                readaloud: format == .readaloud ? asset : nil
            )

            if success {
                uploadProgress = nil
                await refreshBookMetadata()
            } else {
                errorMessage = "Upload failed"
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }

        isUploading = false
        uploadProgress = nil
    }

    private func startAlignment(restart: Bool) async {
        isStartingAlignment = true
        errorMessage = nil

        let success = await StorytellerActor.shared.startAlignment(for: item.uuid, restart: restart)
        if success {
            await refreshBookMetadata()
        } else {
            errorMessage = "Failed to start alignment"
        }

        isStartingAlignment = false
    }

    private func cancelAlignment() async {
        isCancelingAlignment = true
        errorMessage = nil

        let success = await StorytellerActor.shared.cancelAlignment(for: item.uuid)
        if success {
            await refreshBookMetadata()
        } else {
            errorMessage = "Failed to cancel alignment"
        }

        isCancelingAlignment = false
    }

    private func deleteBook() async {
        isDeleting = true
        errorMessage = nil

        for category in [LocalMediaCategory.ebook, .audio, .synced] {
            if mediaViewModel.isCategoryDownloaded(category, for: item) {
                mediaViewModel.deleteDownload(for: item, category: category)
            }
        }

        let success = await StorytellerActor.shared.deleteBook(item.uuid, includeAssets: .all)
        if success {
            await StorytellerActor.shared.fetchLibraryInformation()
            dismiss()
        } else {
            errorMessage = "Failed to delete book from server"
            isDeleting = false
        }
    }

    private func refreshBookMetadata() async {
        await StorytellerActor.shared.fetchLibraryInformation()
    }
}
#endif
