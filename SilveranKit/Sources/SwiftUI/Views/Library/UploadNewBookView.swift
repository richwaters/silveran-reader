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

    private enum UploadResult {
        case success
        case failure(String)
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    fileRow(
                        label: "Ebook",
                        selectedURL: selectedEbookURL,
                        onClear: { selectedEbookURL = nil },
                        onSelect: selectEbook
                    )

                    fileRow(
                        label: "Audiobook",
                        selectedURL: selectedAudiobookURL,
                        onClear: { selectedAudiobookURL = nil },
                        onSelect: selectAudiobook
                    )

                    fileRow(
                        label: "Readaloud",
                        selectedURL: selectedReadaloudURL,
                        onClear: { selectedReadaloudURL = nil },
                        onSelect: selectReadaloud
                    )
                } header: {
                    Text("Select Files")
                } footer: {
                    Text("Select up to three formats to upload. The book will be created from the uploaded media. Other formats can be added later.")
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
                                Text("Upload complete")
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

                Button("Upload") {
                    Task {
                        await uploadBook()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading || !hasAnyFileSelected || uploadResult != nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 340)
    }

    @ViewBuilder
    private func fileRow(
        label: String,
        selectedURL: URL?,
        onClear: @escaping () -> Void,
        onSelect: @escaping () -> Void
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

    private func resetForNewUpload() {
        selectedEbookURL = nil
        selectedAudiobookURL = nil
        selectedReadaloudURL = nil
        uploadResult = nil
        uploadProgress = nil
        bookUUID = UUID().uuidString
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
        guard hasAnyFileSelected else { return }

        await MainActor.run {
            isUploading = true
            uploadProgress = "Preparing..."
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
                    relativePath: nil
                )
            }

            if let url = selectedAudiobookURL {
                await MainActor.run { uploadProgress = "Reading audiobook..." }
                let data = try Data(contentsOf: url)
                let contentType = url.pathExtension.lowercased() == "m4b" ? "audio/mp4" : "audio/mpeg"
                audiobookAsset = StorytellerUploadAsset(
                    format: .audiobook,
                    filename: url.lastPathComponent,
                    data: data,
                    contentType: contentType,
                    relativePath: nil
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
                    relativePath: nil
                )
            }

            await MainActor.run { uploadProgress = "Uploading..." }

            let success = await StorytellerActor.shared.uploadBookAssets(
                bookUUID: bookUUID,
                ebook: ebookAsset,
                audiobook: audiobookAsset,
                readaloud: readaloudAsset
            )

            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                uploadResult = success ? .success : .failure("Upload failed. Your server may not support this feature yet. Please ensure you're running the latest server version.")
            }
            await StorytellerActor.shared.fetchLibraryInformation()
        } catch {
            await MainActor.run {
                isUploading = false
                uploadProgress = nil
                uploadResult = .failure("Failed to read files: \(error.localizedDescription)")
            }
            await StorytellerActor.shared.fetchLibraryInformation()
        }
    }
}
#endif
