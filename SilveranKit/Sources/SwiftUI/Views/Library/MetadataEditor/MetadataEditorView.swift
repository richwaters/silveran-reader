import SwiftUI

public struct MetadataEditorView: View {
    public let initialBookIds: [String]
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var viewModel = MetadataEditorViewModel()
    @State private var sidebarSelection: Set<String> = []
    @AppStorage("metadataEditor.hideWarning") private var hideWarning = false
    @State private var showWarning = true
    @State private var showHardcoverImport = false
    @State private var showErrorDetail = false
    @State private var revertBookId: String?

    public init(initialBookIds: [String]) {
        self.initialBookIds = initialBookIds
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showWarning && !hideWarning {
                warningBanner
            }

            NavigationSplitView {
                bookListSidebar
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
                MetadataEditorBookForm(
                    viewModel: viewModel
                )
                .frame(minWidth: 850)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)

            Divider()
            bottomBar
        }
        .frame(minWidth: 1300, minHeight: 500)
        .onAppear {
            viewModel.addBooks(ids: initialBookIds, from: mediaViewModel.library)
            sidebarSelection = viewModel.selectedBookId.map { [$0] } ?? []
        }
        .onDisappear {
            viewModel.books.removeAll()
            viewModel.selectedBookId = nil
            viewModel.saveResults.removeAll()
            viewModel.saveError = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .metadataEditorAddBooks)) {
            notification in
            guard let bookIds = MetadataEditorNotification.bookIds(from: notification) else {
                return
            }
            viewModel.addBooks(ids: bookIds, from: mediaViewModel.library)
            sidebarSelection = viewModel.selectedBookId.map { [$0] } ?? []
        }
        .sheet(isPresented: $showHardcoverImport) {
            if let book = viewModel.selectedBook {
                HardcoverImportView(
                    bookTitle: book.title,
                    bookAuthor: book.authors.first,
                    onImport: { details, fields in
                        viewModel.applyImport(details: details, fields: fields, for: book.id)
                    },
                    onAutoImportAll: { fields in
                        Task { @MainActor in await viewModel.autoImportAll(fields: fields) }
                    }
                )
            }
        }
        .alert(
            "Revert All Changes?",
            isPresented: Binding(
                get: { revertBookId != nil },
                set: { if !$0 { revertBookId = nil } }
            )
        ) {
            Button("Revert", role: .destructive) {
                if let id = revertBookId {
                    viewModel.revertAllFields(for: id)
                }
                revertBookId = nil
            }
            Button("Cancel", role: .cancel) {
                revertBookId = nil
            }
        } message: {
            if let id = revertBookId,
               let book = viewModel.books.first(where: { $0.id == id })
            {
                Text("This will discard all edits to \"\(book.displayTitle)\" and restore the original server values.")
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

    // MARK: - Book List Sidebar

    @ViewBuilder
    private var bookListSidebar: some View {
        List(selection: $sidebarSelection) {
            ForEach(viewModel.books) { book in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.displayTitle)
                            .lineLimit(1)
                            .font(.body)
                        if let author = book.authors.first, !author.isEmpty {
                            Text(author)
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if book.hasDirtyFields {
                        Button {
                            revertBookId = book.id
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Revert all changes")
                    }
                    if viewModel.saveResults[book.id] == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if viewModel.saveResults[book.id] == false {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .tag(book.id)
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("Remove Selected") {
                viewModel.removeBooks(ids: sidebarSelection)
                sidebarSelection = viewModel.selectedBookId.map { [$0] } ?? []
            }
            .disabled(sidebarSelection.isEmpty)
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            let added = newValue.subtracting(oldValue)
            if let newId = added.first {
                viewModel.selectedBookId = newId
            } else if !newValue.contains(viewModel.selectedBookId ?? "") {
                viewModel.selectedBookId = newValue.first
            }
        }
    }

    // MARK: - Bottom Bar

    private var currentBookErrors: [MetadataEditorViewModel.ValidationError] {
        guard let bookId = viewModel.selectedBookId else { return [] }
        return viewModel.validationErrors(for: bookId)
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if viewModel.isAutoImporting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(
                        "Importing \(viewModel.autoImportProgress.current + 1)/\(viewModel.autoImportProgress.total)..."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.autoImportError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .lineLimit(1)
            } else if let error = viewModel.saveError {
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

            Button("Download Metadata/Covers from Hardcover") {
                showHardcoverImport = true
            }
            .disabled(viewModel.selectedBookId == nil)

            Button("Save Selected to Storyteller") {
                guard let bookId = viewModel.selectedBookId else { return }
                Task { @MainActor in await viewModel.saveSingle(bookId) }
            }
            .disabled(
                viewModel.isSaving || viewModel.selectedBookId == nil
                    || !(viewModel.books.first { $0.id == viewModel.selectedBookId }?.hasDirtyFields
                        ?? false)
                    || viewModel.hasValidationErrors(for: viewModel.selectedBookId ?? "")
            )

            Button("Save All to Storyteller") {
                Task { @MainActor in await viewModel.saveAll() }
            }
            .disabled(
                viewModel.isSaving || !viewModel.hasAnyDirtyBooks
                    || viewModel.hasAnyValidationErrors)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(12)
    }
}
