import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

public struct UploadNewBookData: Codable, Hashable {
    public init() {}
}

public struct UploadNewBookView: View {
    @Environment(MediaViewModel.self) private var mediaViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEbookURL: URL?
    @State private var selectedAudiobookURL: URL?
    @State private var selectedReadaloudURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: String?
    @State private var uploadResult: UploadResult?
    @State private var bookUUID = UUID().uuidString
    @State private var bookSources: [BookSourceRecord] = []
    @State private var selectedSourceID: BookSourceID?

    private enum UploadResult {
        case success
        case failure(String)
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Destination") {
                    Picker("Upload To", selection: selectedSourceBinding) {
                        ForEach(bookSources) { source in
                            Label(source.name, systemImage: iconName(for: source.kind))
                                .tag(source.id)
                        }
                    }
                    .disabled(isUploading || uploadResult != nil || bookSources.isEmpty)
                }

                Section {
                    fileRow(
                        label: "Ebook",
                        selectedURL: selectedEbookURL,
                        onClear: { selectedEbookURL = nil },
                        onSelect: selectEbook,
                    )

                    fileRow(
                        label: "Audiobook",
                        selectedURL: selectedAudiobookURL,
                        onClear: { selectedAudiobookURL = nil },
                        onSelect: selectAudiobook,
                    )

                    fileRow(
                        label: "Readaloud",
                        selectedURL: selectedReadaloudURL,
                        onClear: { selectedReadaloudURL = nil },
                        onSelect: selectReadaloud,
                    )
                } header: {
                    Text("Select Files")
                } footer: {
                    Text(
                        "Select up to three formats. Storyteller destinations upload to the server; folder destinations copy files into that folder source."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let result = uploadResult {
                    Section {
                        switch result {
                            case .success:
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Book added")
                                }
                            case .failure(let message):
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(message)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if uploadResult != nil {
                    Button("Upload Another") {
                        resetForNewUpload()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                    if let progress = uploadProgress {
                        Text(progress)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button(primaryActionTitle) {
                    Task {
                        await uploadBook()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isUploading || !hasAnyFileSelected || uploadResult != nil
                        || selectedSourceID == nil,
                )
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 340)
        .task {
            await loadSources()
        }
    }

    private var selectedSourceBinding: Binding<BookSourceID> {
        Binding(
            get: {
                selectedSourceID ?? bookSources.first?.id ?? ""
            },
            set: { selectedSourceID = $0 },
        )
    }

    @ViewBuilder
    private func fileRow(
        label: String,
        selectedURL: URL?,
        onClear: @escaping () -> Void,
        onSelect: @escaping () -> Void,
    ) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            Spacer()
            if let url = selectedURL {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isUploading || uploadResult != nil)
            }
            Button("Select...") {
                onSelect()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isUploading || uploadResult != nil)
        }
    }

    private var hasAnyFileSelected: Bool {
        selectedEbookURL != nil || selectedAudiobookURL != nil || selectedReadaloudURL != nil
    }

    private var selectedSource: BookSourceRecord? {
        guard let selectedSourceID else { return nil }
        return bookSources.first { $0.id == selectedSourceID }
    }

    private var primaryActionTitle: String {
        selectedSource?.kind == .localFolder ? "Add" : "Upload"
    }

    private func resetForNewUpload() {
        selectedEbookURL = nil
        selectedAudiobookURL = nil
        selectedReadaloudURL = nil
        uploadResult = nil
        uploadProgress = nil
        bookUUID = UUID().uuidString
    }

    private func loadSources() async {
        let sources = await BookServiceActor.shared.bookSources
        await MainActor.run {
            bookSources = sources
            selectedSourceID = selectedSourceID ?? sources.first?.id
        }
    }

    private func iconName(for kind: BookSourceKind) -> String {
        switch kind {
            case .storyteller:
                return "server.rack"
            case .localFolder:
                return "folder"
        }
    }

    private func selectEbook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epub]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an EPUB ebook file"

        if panel.runModal() == .OK {
            selectedEbookURL = panel.url
        }
    }

    private func selectAudiobook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Audio, .mp3, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an audiobook file (m4b, mp3, etc.)"

        if panel.runModal() == .OK {
            selectedAudiobookURL = panel.url
        }
    }

    private func selectReadaloud() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epub]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a readaloud EPUB file (with media overlays)"

        if panel.runModal() == .OK {
            selectedReadaloudURL = panel.url
        }
    }

    private func uploadBook() async {
        guard hasAnyFileSelected, let sourceID = selectedSourceID else { return }
        guard let source = bookSources.first(where: { $0.id == sourceID }) else { return }

        await MainActor.run {
            isUploading = true
            uploadProgress = "Preparing..."
        }

        if source.kind == .localFolder {
            await importIntoFolderSource(source)
            return
        }

        var ebookAsset: StorytellerUploadAsset?
        var audiobookAsset: StorytellerUploadAsset?
        var readaloudAsset: StorytellerUploadAsset?

        do {
            if let url = selectedEbookURL {
                await MainActor.run { uploadProgress = "Reading ebook..." }
                let data = try Data(contentsOf: url)
                ebookAsset = StorytellerUploadAsset(
                    format: .ebook,
                    filename: url.lastPathComponent,
                    data: data,
                    contentType: "application/epub+zip",
                    relativePath: nil,
                )
            }

            if let url = selectedAudiobookURL {
                await MainActor.run { uploadProgress = "Reading audiobook..." }
                let data = try Data(contentsOf: url)
                let contentType =
                    url.pathExtension.lowercased() == "m4b" ? "audio/mp4" : "audio/mpeg"
                audiobookAsset = StorytellerUploadAsset(
                    format: .audiobook,
                    filename: url.lastPathComponent,
                    data: data,
                    contentType: contentType,
                    relativePath: nil,
                )
            }

            if let url = selectedReadaloudURL {
                await MainActor.run { uploadProgress = "Reading readaloud..." }
                let data = try Data(contentsOf: url)
                readaloudAsset = StorytellerUploadAsset(
                    format: .readaloud,
                    filename: url.lastPathComponent,
                    data: data,
                    contentType: "application/epub+zip",
                    relativePath: nil,
                )
            }

            await MainActor.run { uploadProgress = "Uploading..." }

            let success = await BookServiceActor.shared.uploadBookAssets(
                bookUUID: bookUUID,
                sourceID: sourceID,
                ebook: ebookAsset,
                audiobook: audiobookAsset,
                readaloud: readaloudAsset,
            )

            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                uploadResult =
                    success
                    ? .success
                    : .failure(
                        "Upload failed. Your server may not support this feature yet. Please ensure you're running the latest server version."
                    )
            }
            await BookServiceActor.shared.fetchLibraryInformation()
        } catch {
            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                uploadResult = .failure("Failed to read files: \(error.localizedDescription)")
            }
            await BookServiceActor.shared.fetchLibraryInformation()
        }
    }

    private func importIntoFolderSource(_ source: BookSourceRecord) async {
        let folderSource = FolderSourceActor(sourceRecord: source)
        let importTitle = selectedEbookURL?.deletingPathExtension().lastPathComponent
            ?? selectedReadaloudURL?.deletingPathExtension().lastPathComponent
            ?? selectedAudiobookURL?.deletingPathExtension().lastPathComponent
            ?? "Book"

        do {
            if let url = selectedEbookURL {
                await MainActor.run { uploadProgress = "Copying ebook..." }
                _ = try await folderSource.importMedia(
                    from: url,
                    category: .ebook,
                    bookName: importTitle,
                    bookUUID: bookUUID,
                )
            }

            if let url = selectedAudiobookURL {
                await MainActor.run { uploadProgress = "Copying audiobook..." }
                _ = try await folderSource.importMedia(
                    from: url,
                    category: .audio,
                    bookName: importTitle,
                    bookUUID: bookUUID,
                )
            }

            if let url = selectedReadaloudURL {
                await MainActor.run { uploadProgress = "Copying readaloud..." }
                _ = try await folderSource.importMedia(
                    from: url,
                    category: .synced,
                    bookName: importTitle,
                    bookUUID: bookUUID,
                )
            }

            _ = await BookServiceActor.shared.fetchLibraryInformation(sourceID: source.id)
            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                uploadResult = .success
            }
        } catch {
            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                uploadResult = .failure("Failed to add files: \(error.localizedDescription)")
            }
        }
    }
}
#endif
