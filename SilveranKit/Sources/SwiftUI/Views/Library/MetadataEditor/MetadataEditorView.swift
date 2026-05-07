import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct MetadataEditorView: View {
    public let initialBookIds: [String]
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var viewModel = MetadataEditorViewModel()
    @State private var selectedSection: MetadataEditorSection = .covers
    @State private var selectedCoverScope: CoversTab.CoverScope = .audiobook
    @AppStorage("metadataEditor.hideWarning") private var hideWarning = false
    @State private var showWarning = true
    @State private var showHardcoverImport = false
    @State private var showHardcoverDataDump = false
    @State private var showErrorDetail = false

    public init(initialBookIds: [String]) {
        self.initialBookIds = initialBookIds
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showWarning && !hideWarning {
                warningBanner
            }

            NavigationSplitView {
                sectionSidebar
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
                sectionContent
                    .frame(minWidth: 850)
                    .clipped()
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)

            Divider()
            bottomBar
        }
        .frame(minWidth: 1300, minHeight: 500)
        .navigationTitle(viewModel.selectedBook?.displayTitle ?? "Edit Metadata")
        #if os(macOS)
        .background(
            MetadataEditorWindowController(
                title: windowTitle,
                shouldPromptBeforeClose: viewModel.hasAnyDirtyBooks,
                isSaving: viewModel.isSaving,
                onSaveBeforeClose: saveBeforeClosing
            )
            .frame(width: 0, height: 0)
        )
        #endif
        .onAppear {
            viewModel.addBooks(ids: Array(initialBookIds.prefix(1)), from: mediaViewModel.library)
        }
        .onDisappear {
            viewModel.books.removeAll()
            viewModel.selectedBookId = nil
            viewModel.saveResults.removeAll()
            viewModel.saveError = nil
            viewModel.clearTransientImportState()
        }
        .sheet(isPresented: $showHardcoverImport) {
            if let book = viewModel.selectedBook {
                HardcoverImportView(
                    bookTitle: book.title,
                    bookAuthor: book.authors.first,
                    onImport: { imports, fields in
                        viewModel.applyImport(imports: imports, fields: fields, for: book.id)
                    }
                )
            }
        }
    }

    // MARK: - Warning Banner

    @ViewBuilder
    private var warningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Experimental Feature")
                    .font(.headline)
                Text(
                    "Back up your database before editing metadata. This feature could cause data corruption."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Don't show again", isOn: $hideWarning)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .font(.callout)

            Button(action: { showWarning = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.yellow.opacity(0.1))
        .clipped()
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.yellow.opacity(0.3)),
            alignment: .bottom
        )
    }

    // MARK: - Section Sidebar

    @ViewBuilder
    private var sectionSidebar: some View {
        List(selection: $selectedSection) {
            ForEach(MetadataEditorSection.allCases) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var sectionContent: some View {
        MetadataEditorBookForm(
            viewModel: viewModel,
            selectedSection: $selectedSection,
            selectedCoverScope: $selectedCoverScope,
            openHardcoverImport: { showHardcoverImport = true }
        )
    }

    // MARK: - Window Title

    private var windowTitle: String {
        guard let book = viewModel.selectedBook else { return "Edit Metadata" }
        return "Edit Metadata - \(book.displayTitle)"
    }

    #if os(macOS)
    private func saveBeforeClosing() async -> Bool {
        guard let bookId = viewModel.selectedBookId else { return true }
        let errors = viewModel.validationErrors(for: bookId)
        guard errors.isEmpty else {
            viewModel.saveError = errors.map(\.message).joined(separator: "; ")
            return false
        }

        await viewModel.saveSingle(bookId, mediaViewModel: mediaViewModel)
        return !(viewModel.books.first { $0.id == bookId }?.hasDirtyFields ?? false)
            && viewModel.saveError == nil
    }

    private struct MetadataEditorWindowController: NSViewRepresentable {
        let title: String
        let shouldPromptBeforeClose: Bool
        let isSaving: Bool
        let onSaveBeforeClose: () async -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                view.window?.title = title
                view.window?.delegate = context.coordinator
                context.coordinator.window = view.window
            }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.title = title
            context.coordinator.shouldPromptBeforeClose = shouldPromptBeforeClose
            context.coordinator.isSaving = isSaving
            context.coordinator.onSaveBeforeClose = onSaveBeforeClose
            DispatchQueue.main.async {
                view.window?.title = title
                view.window?.delegate = context.coordinator
                context.coordinator.window = view.window
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(
                title: title,
                shouldPromptBeforeClose: shouldPromptBeforeClose,
                isSaving: isSaving,
                onSaveBeforeClose: onSaveBeforeClose
            )
        }

        final class Coordinator: NSObject, NSWindowDelegate {
            var title: String
            var shouldPromptBeforeClose: Bool
            var isSaving: Bool
            var onSaveBeforeClose: () async -> Bool
            weak var window: NSWindow?
            private var allowClose = false

            init(
                title: String,
                shouldPromptBeforeClose: Bool,
                isSaving: Bool,
                onSaveBeforeClose: @escaping () async -> Bool
            ) {
                self.title = title
                self.shouldPromptBeforeClose = shouldPromptBeforeClose
                self.isSaving = isSaving
                self.onSaveBeforeClose = onSaveBeforeClose
            }

            func windowShouldClose(_ sender: NSWindow) -> Bool {
                guard !allowClose else { return true }
                guard shouldPromptBeforeClose else { return true }
                guard !isSaving else { return false }

                let alert = NSAlert()
                alert.messageText = "Save changes before closing?"
                alert.informativeText =
                    "The metadata editor has unsaved changes. Save them to Storyteller before closing?"
                alert.addButton(withTitle: "Save")
                alert.addButton(withTitle: "Don't Save")
                alert.addButton(withTitle: "Cancel")

                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    Task { @MainActor in
                        if await onSaveBeforeClose() {
                            allowClose = true
                            sender.close()
                            allowClose = false
                        }
                    }
                    return false
                case .alertSecondButtonReturn:
                    return true
                default:
                    return false
                }
            }
        }
    }

    #endif

    // MARK: - Bottom Bar

    private var currentBookErrors: [MetadataEditorViewModel.ValidationError] {
        guard let bookId = viewModel.selectedBookId else { return [] }
        return viewModel.validationErrors(for: bookId)
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if let error = viewModel.saveError {
                HStack(spacing: 4) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button {
                        showErrorDetail = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showErrorDetail) {
                        Text(error)
                            .font(.callout)
                            .padding()
                            .frame(maxWidth: 400)
                            .textSelection(.enabled)
                    }
                }
            } else if !currentBookErrors.isEmpty {
                Label(
                    currentBookErrors.map(\.message).joined(separator: "; "),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
                .font(.callout)
            }

            Spacer()

            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button {
                showHardcoverDataDump = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedBookId == nil)
            .help("Show raw Hardcover imported data")
            .popover(isPresented: $showHardcoverDataDump, arrowEdge: .bottom) {
                hardcoverDataDumpPopover
            }

            Button("Download Metadata/Covers from Hardcover") {
                showHardcoverImport = true
            }
            .disabled(viewModel.selectedBookId == nil)

            itunesCoversButton

            Button("Save Current to Storyteller") {
                guard let bookId = viewModel.selectedBookId else { return }
                Task { @MainActor in
                    await viewModel.saveSingle(bookId, mediaViewModel: mediaViewModel)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.isSaving || viewModel.selectedBookId == nil
                    || !(viewModel.books.first { $0.id == viewModel.selectedBookId }?.hasDirtyFields
                        ?? false)
                    || viewModel.hasValidationErrors(for: viewModel.selectedBookId ?? "")
            )
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(12)
    }

    private var hardcoverDataDumpText: String {
        guard let bookId = viewModel.selectedBookId else { return "No book selected." }
        return viewModel.rawHardcoverDataDump(for: bookId)
    }

    private var hardcoverDataDumpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hardcover Imported Data")
                    .font(.headline)

                Spacer()

                #if os(macOS)
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hardcoverDataDumpText, forType: .string)
                }
                .controlSize(.small)
                #endif
            }

            TextEditor(text: .constant(hardcoverDataDumpText))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(width: 720, height: 520)
        }
        .padding()
    }

    @ViewBuilder
    private var itunesCoversButton: some View {
        Button("Download Covers from iTunes") {
            guard let book = viewModel.selectedBook else { return }
            viewModel.searchItunes(book: book)
        }
        .disabled(
            viewModel.selectedBook == nil
                || viewModel.selectedBookId.map { viewModel.isSearchingItunes(for: $0) } ?? false
        )
        .help("Download covers from iTunes")
    }
}
