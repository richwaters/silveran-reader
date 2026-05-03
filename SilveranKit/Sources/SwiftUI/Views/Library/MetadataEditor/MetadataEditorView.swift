import SwiftUI

public struct MetadataEditorView: View {
    public let initialBookIds: [String]
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var viewModel = MetadataEditorViewModel()
    @AppStorage("metadataEditor.hideWarning") private var hideWarning = false
    @State private var showWarning = true

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
                    viewModel: viewModel,
                    availableStatuses: mediaViewModel.availableStatuses
                )
                .frame(minWidth: 400)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)

            Divider()
            bottomBar
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            viewModel.addBooks(ids: initialBookIds, from: mediaViewModel.library)
        }
        .onReceive(NotificationCenter.default.publisher(for: .metadataEditorAddBooks)) {
            notification in
            guard let bookIds = MetadataEditorNotification.bookIds(from: notification) else {
                return
            }
            viewModel.addBooks(ids: bookIds, from: mediaViewModel.library)
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
                .toggleStyle(.checkbox)
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
        List(selection: Binding(
            get: { viewModel.selectedBookId },
            set: { viewModel.selectedBookId = $0 }
        )) {
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
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
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
                .contextMenu {
                    Button("Remove from Editor") {
                        viewModel.removeBook(id: book.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Bottom Bar

    private var currentBookErrors: [MetadataEditorViewModel.ValidationError] {
        guard let bookId = viewModel.selectedBookId else { return [] }
        return viewModel.validationErrors(for: bookId)
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if let error = viewModel.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
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

            Button("Save Selected to Server") {
                guard let bookId = viewModel.selectedBookId else { return }
                Task { @MainActor in await viewModel.saveSingle(bookId) }
            }
            .disabled(
                viewModel.isSaving || viewModel.selectedBookId == nil
                    || !(viewModel.books.first { $0.id == viewModel.selectedBookId }?.hasDirtyFields
                        ?? false)
                    || viewModel.hasValidationErrors(for: viewModel.selectedBookId ?? "")
            )

            Button("Save All to Server") {
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
