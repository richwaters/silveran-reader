import SwiftUI
import AppKit
import StoryAlignCore
import UniformTypeIdentifiers

public struct ReadaloudGeneratorView: View {
    @State private var viewModel = ReadaloudGeneratorViewModel()
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inputFilesSection
                    modelSection
                    optionsSection
                    if !viewModel.availableChapters.isEmpty {
                        chapterRangeSection
                    }
                    outputSection
                }
                .padding(20)
            }
            .onChange(of: viewModel.epubURL) { _, _ in
                viewModel.loadChapters()
            }
            if case .processing = viewModel.state {
                Divider()
                progressSection
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            if case .error(let message) = viewModel.state {
                Divider()
                errorSection(message: message)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            if case .completed(let url) = viewModel.state {
                Divider()
                completedSection(url: url)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            Divider()
            footerView
        }
        .frame(width: 500, height: 650)
    }

    private var headerView: some View {
        VStack(spacing: 4) {
            Text("Create Readaloud")
                .font(.headline)
            Text("Align an audiobook with an EPUB to create a synchronized readaloud")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var inputFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Files")
                .font(.headline)

            filePickerRow(
                label: "EPUB:",
                url: viewModel.epubURL,
                placeholder: "Select EPUB file...",
                allowedTypes: [.epub]
            ) { url in
                viewModel.epubURL = url
            }

            filePickerRow(
                label: "Audiobook:",
                url: viewModel.audioURL,
                placeholder: "Select M4B audiobook...",
                allowedTypes: [UTType(filenameExtension: "m4b")!]
            ) { url in
                viewModel.audioURL = url
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whisper Model")
                .font(.headline)

            HStack {
                Picker("Model:", selection: $viewModel.selectedModelSize) {
                    ForEach(WhisperModelSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isModelDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Downloaded")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Button("Download") {
                        viewModel.downloadModel()
                    }
                    .disabled(viewModel.state == .processing)
                }
            }

            if case .downloading(let progress) = viewModel.state {
                ProgressView(value: progress) {
                    Text("Downloading model...")
                        .font(.caption)
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)

            HStack {
                Text("Granularity:")
                Picker("", selection: $viewModel.selectedGranularity) {
                    Text("Sentence").tag(Granularity.sentence)
                    Text("Phrase").tag(Granularity.phrase)
                    Text("Word").tag(Granularity.word)
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Text("Sentence level is recommended for most books.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chapterRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapter Range")
                .font(.headline)

            HStack(spacing: 16) {
                HStack {
                    Text("Start:")
                    Picker("", selection: $viewModel.startChapterIndex) {
                        Text("Beginning").tag(nil as Int?)
                        ForEach(viewModel.availableChapters.indices, id: \.self) { i in
                            Text(viewModel.availableChapters[i].name).tag(i as Int?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("End:")
                    Picker("", selection: $viewModel.endChapterIndex) {
                        Text("End").tag(nil as Int?)
                        ForEach(viewModel.availableChapters.indices, id: \.self) { i in
                            Text(viewModel.availableChapters[i].name).tag(i as Int?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }

            Text("Leave as Beginning/End to include all chapters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var outputSection: some View {
        let suggestedName: String? = viewModel.epubURL.map {
            $0.deletingPathExtension().lastPathComponent + "-readaloud.epub"
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Output")
                .font(.headline)

            filePickerRow(
                label: "Save to:",
                url: viewModel.outputURL,
                placeholder: "Select output location...",
                allowedTypes: [.epub],
                isSavePanel: true,
                suggestedFilename: suggestedName
            ) { url in
                viewModel.outputURL = url
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.headline)

            ProgressView(value: viewModel.overallProgress) {
                HStack {
                    Text(viewModel.currentStage.displayName)
                        .font(.caption)
                    Spacer()
                    Text("\(Int(viewModel.overallProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.currentMessage.isEmpty {
                Text(viewModel.currentMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.headline)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completedSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Completed")
                    .font(.headline)
            }
            Text("Readaloud created successfully!")
                .font(.caption)

            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                }
                Button("Open") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerView: some View {
        let isDisabled = !viewModel.canStart || !viewModel.isModelDownloaded

        return VStack(alignment: .trailing, spacing: 8) {
            if isDisabled {
                HStack {
                    Spacer()
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Button("Cancel") {
                    if case .processing = viewModel.state {
                        viewModel.cancel()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    viewModel.startAlignment()
                } label: {
                    Text("Create Readaloud")
                        .foregroundStyle(isDisabled ? Color(nsColor: .disabledControlTextColor) : .white)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDisabled)
                .buttonStyle(.borderedProminent)
                .tint(isDisabled ? Color(nsColor: .disabledControlTextColor) : .accentColor)
            }
        }
        .padding()
    }

    private var disabledReason: String {
        if viewModel.epubURL == nil {
            return "Select an EPUB file"
        }
        if viewModel.audioURL == nil {
            return "Select an audiobook file"
        }
        if viewModel.outputURL == nil {
            return "Select output location"
        }
        if !viewModel.isModelDownloaded {
            return "Download the Whisper model first"
        }
        return ""
    }

    private func filePickerRow(
        label: String,
        url: URL?,
        placeholder: String,
        allowedTypes: [UTType],
        isSavePanel: Bool = false,
        suggestedFilename: String? = nil,
        onSelect: @escaping (URL?) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .trailing)

            Text(url?.lastPathComponent ?? placeholder)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button("Browse...") {
                if isSavePanel {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = allowedTypes
                    panel.nameFieldStringValue = suggestedFilename ?? url?.lastPathComponent ?? "output.epub"
                    if panel.runModal() == .OK {
                        onSelect(panel.url)
                    }
                } else {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = allowedTypes
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK {
                        onSelect(panel.url)
                    }
                }
            }
        }
    }
}
