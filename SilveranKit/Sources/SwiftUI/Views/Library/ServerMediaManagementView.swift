#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ServerMediaManagementData: Codable, Hashable {
    public let bookId: String

    public init(bookId: String) {
        self.bookId = bookId
    }
}

public struct ServerMediaManagementView: View {
    let bookId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaViewModel.self) private var mediaViewModel

    @State private var isUploading = false
    @State private var uploadingFormat: StorytellerBookFormat?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isStartingAlignment = false
    @State private var isCancelingAlignment = false
    @State private var errorMessage: String?
    @State private var hoveredDownloadCategory: LocalMediaCategory?

    public init(bookId: String) {
        self.bookId = bookId
    }

    private var item: BookMetadata? {
        mediaViewModel.library.bookMetaData.first { $0.id == bookId }
    }

    private var isValidServerBook: Bool {
        guard item != nil else { return false }
        return mediaViewModel.isServerBook(bookId)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isValidServerBook, let item {
                headerView(item: item)
                Divider()

                Form {
                    Section("Local Downloads") {
                        localMediaRow(item: item, category: .ebook, label: "Ebook")
                        localMediaRow(item: item, category: .audio, label: "Audiobook")
                        localMediaRow(item: item, category: .synced, label: "Readaloud")
                    }

                    Section("Server Media") {
                        serverMediaRow(item: item, format: .ebook, label: "Ebook", asset: item.ebook)
                        serverMediaRow(item: item, format: .audiobook, label: "Audiobook", asset: item.audiobook)
                        serverReadaloudRow(item: item)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)

                if let error = errorMessage {
                    Divider()
                    errorView(message: error)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }

                Divider()
                footerView(item: item)
            } else {
                invalidBookView
            }
        }
        .frame(width: 480, height: 540)
        .confirmationDialog(
            "Delete Book from Server?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item {
                    Task { await deleteBook(item: item) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the book and all its media from the server and remove any local downloads. This cannot be undone.")
        }
    }

    private var invalidBookView: some View {
        VStack(spacing: 0) {
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
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private func headerView(item: BookMetadata) -> some View {
        HStack(spacing: 12) {
            coverImage(item: item)
                .frame(width: 50, height: 75)
                .cornerRadius(4)
                .clipped()

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

    @ViewBuilder
    private func localMediaRow(item: BookMetadata, category: LocalMediaCategory, label: String) -> some View {
        let isDownloaded = mediaViewModel.isCategoryDownloaded(category, for: item)
        let isDownloading = mediaViewModel.isCategoryDownloadInProgress(for: item, category: category)
        let progress = mediaViewModel.downloadProgressFraction(for: item, category: category)
        let serverHasMedia = serverHasMedia(for: category, item: item)
        let isHovered = hoveredDownloadCategory == category

        LabeledContent(label) {
            HStack(spacing: 12) {
                if isDownloading {
                    Button {
                        mediaViewModel.cancelDownload(for: item, category: category)
                    } label: {
                        HStack(spacing: 6) {
                            if isHovered {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.blue)
                            } else if let progress {
                                ZStack {
                                    Circle()
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(Color.blue, lineWidth: 2)
                                        .rotationEffect(.degrees(-90))
                                }
                                .frame(width: 14, height: 14)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                            Text("Downloading...")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredDownloadCategory = hovering ? category : nil
                    }
                } else if isDownloaded {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Downloaded")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button("Delete", role: .destructive) {
                        mediaViewModel.deleteDownload(for: item, category: category)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 80)
                } else if serverHasMedia {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                        Text("Not downloaded")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button("Download") {
                        mediaViewModel.startDownload(for: item, category: category)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 80)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.tertiary)
                        Text("Not on server")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Spacer().frame(width: 80)
                }
            }
        }
    }

    private func serverHasMedia(for category: LocalMediaCategory, item: BookMetadata) -> Bool {
        switch category {
        case .ebook:
            return item.ebook != nil && item.ebook?.isMissing != true
        case .audio:
            return item.audiobook != nil && item.audiobook?.isMissing != true
        case .synced:
            if let readaloud = item.readaloud {
                return !readaloud.isMissing && readaloud.status?.uppercased() == "ALIGNED"
            }
            return false
        }
    }

    @ViewBuilder
    private func serverMediaRow(item: BookMetadata, format: StorytellerBookFormat, label: String, asset: BookAsset?) -> some View {
        let isUploadingThis = isUploading && uploadingFormat == format
        let types: [UTType] = format == .ebook ? [.epub] : audioTypes

        LabeledContent(label) {
            HStack(spacing: 12) {
                if isUploadingThis {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Uploading...")
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .trailing)

                    Spacer().frame(width: 80)
                } else if let asset {
                    Group {
                        if asset.isMissing {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("Missing")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Available")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button("Replace") {
                        selectAndUploadFile(format: format, types: types, item: item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isUploading || isDeleting)
                    .frame(width: 80)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                        Text("Not on server")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button("Upload") {
                        selectAndUploadFile(format: format, types: types, item: item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isUploading || isDeleting)
                    .frame(width: 80)
                }
            }
        }
    }

    @ViewBuilder
    private func serverReadaloudRow(item: BookMetadata) -> some View {
        let isUploadingThis = isUploading && uploadingFormat == .readaloud

        LabeledContent("Readaloud") {
            HStack(spacing: 12) {
                if isUploadingThis {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Uploading...")
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .trailing)

                    Spacer().frame(width: 80)
                } else if let readaloud = item.readaloud {
                    if readaloud.isMissing {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Missing")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 130, alignment: .trailing)

                        Button("Replace") {
                            selectAndUploadFile(format: .readaloud, types: [.epub], item: item)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isUploading || isDeleting)
                        .frame(width: 80)
                    } else if let status = readaloud.status?.uppercased() {
                        switch status {
                        case "ALIGNED":
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Available")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 130, alignment: .trailing)

                            Button("Replace") {
                                selectAndUploadFile(format: .readaloud, types: [.epub], item: item)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isUploading || isDeleting)
                            .frame(width: 80)
                        case "PROCESSING":
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                if let stage = readaloud.currentStage, let progress = readaloud.stageProgress {
                                    Text("\(stage): \(Int(progress * 100))%")
                                        .lineLimit(1)
                                } else {
                                    Text("Processing...")
                                }
                            }
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 130, alignment: .trailing)

                            Button {
                                Task { await cancelAlignment(item: item) }
                            } label: {
                                if isCancelingAlignment {
                                    ProgressView().scaleEffect(0.5)
                                } else {
                                    Text("Cancel")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isCancelingAlignment)
                            .frame(width: 80)
                        case "QUEUED":
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.orange)
                                if let pos = readaloud.queuePosition {
                                    Text("Queued (#\(pos))")
                                } else {
                                    Text("Queued")
                                }
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 130, alignment: .trailing)

                            Button {
                                Task { await cancelAlignment(item: item) }
                            } label: {
                                if isCancelingAlignment {
                                    ProgressView().scaleEffect(0.5)
                                } else {
                                    Text("Cancel")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isCancelingAlignment)
                            .frame(width: 80)
                        case "ERROR", "STOPPED":
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(status.capitalized)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 130, alignment: .trailing)

                            Button {
                                Task { await startAlignment(item: item, restart: true) }
                            } label: {
                                if isStartingAlignment {
                                    ProgressView().scaleEffect(0.5)
                                } else {
                                    Text("Restart Alignment")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isStartingAlignment || isUploading)

                            Button("Upload") {
                                selectAndUploadFile(format: .readaloud, types: [.epub], item: item)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isUploading || isDeleting)
                            .frame(width: 65)
                        default:
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                Text(status)
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 130, alignment: .trailing)

                            Spacer().frame(width: 80)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                            Text("Unknown")
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .trailing)

                        Spacer().frame(width: 80)
                    }
                } else if canStartAlignment(item: item) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                        Text("Not aligned")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button {
                        Task { await startAlignment(item: item, restart: false) }
                    } label: {
                        if isStartingAlignment {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Text("Align")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isStartingAlignment || isUploading)
                    .frame(width: 60)

                    Button("Upload") {
                        selectAndUploadFile(format: .readaloud, types: [.epub], item: item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isUploading || isDeleting)
                    .frame(width: 65)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                        Text("Not on server")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button("Upload") {
                        selectAndUploadFile(format: .readaloud, types: [.epub], item: item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isUploading || isDeleting)
                    .frame(width: 80)
                }
            }
        }
    }

    private func footerView(item: BookMetadata) -> some View {
        HStack {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    if isDeleting {
                        ProgressView().scaleEffect(0.5)
                    }
                    Text("Delete from Server")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isDeleting || isUploading)

            Spacer()

            Button("Done") { dismiss() }
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
            Button("Dismiss") { errorMessage = nil }
        }
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
    private func coverImage(item: BookMetadata) -> some View {
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

    private func canStartAlignment(item: BookMetadata) -> Bool {
        let hasEbook = item.ebook != nil && item.ebook?.isMissing != true
        let hasAudiobook = item.audiobook != nil && item.audiobook?.isMissing != true
        let noReadaloud = item.readaloud == nil
        return hasEbook && hasAudiobook && noReadaloud
    }

    private func canRestartAlignment(item: BookMetadata) -> Bool {
        guard let readaloud = item.readaloud else { return false }
        let status = readaloud.status?.uppercased() ?? ""
        return status == "ERROR" || status == "STOPPED"
    }

    private func isAlignmentInProgress(item: BookMetadata) -> Bool {
        guard let readaloud = item.readaloud else { return false }
        let status = readaloud.status?.uppercased() ?? ""
        return status == "PROCESSING" || status == "QUEUED"
    }

    private func selectAndUploadFile(format: StorytellerBookFormat, types: [UTType], item: BookMetadata) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select file to upload"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await uploadFile(url: url, format: format, item: item)
        }
    }

    private func uploadFile(url: URL, format: StorytellerBookFormat, item: BookMetadata) async {
        isUploading = true
        uploadingFormat = format
        errorMessage = nil

        do {
            let data = try Data(contentsOf: url)
            let asset = StorytellerUploadAsset(
                format: format,
                filename: url.lastPathComponent,
                data: data
            )

            let success = await StorytellerActor.shared.uploadBookAssets(
                bookUUID: item.uuid,
                ebook: format == .ebook ? asset : nil,
                audiobook: format == .audiobook ? asset : nil,
                readaloud: format == .readaloud ? asset : nil
            )

            if success {
                await refreshBookMetadata()
            } else {
                errorMessage = "Upload failed"
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }

        isUploading = false
        uploadingFormat = nil
    }

    private func startAlignment(item: BookMetadata, restart: Bool) async {
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

    private func cancelAlignment(item: BookMetadata) async {
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

    private func deleteBook(item: BookMetadata) async {
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
