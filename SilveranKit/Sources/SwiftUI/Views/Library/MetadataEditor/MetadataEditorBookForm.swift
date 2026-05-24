import SwiftUI

struct MetadataEditorBookForm: View {
    @Bindable var viewModel: MetadataEditorViewModel
    @Binding var selectedScope: MetadataEditorScope
    @Binding var selectedCoverScope: MetadataCoverScope
    let openHardcoverImport: () -> Void
    let revertCurrentBook: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsManageEditions = false

    private var bookId: String? { viewModel.selectedBookId }

    var body: some View {
        Group {
            if let bookId {
                VStack(spacing: 0) {
                    scopePicker
                    Divider()
                    scopeContent(bookId: bookId)
                }
            } else {
                ContentUnavailableView("No Book Selected", systemImage: "book.closed")
            }
        }
    }

    private var scopePicker: some View {
        ZStack {
            Picker("", selection: $selectedScope) {
                ForEach(MetadataEditorScope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            HStack {
                if viewModel.selectedBook?.hasDirtyFields == true {
                    Button(action: revertCurrentBook) {
                        Label("Revert All", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(metadataEditorChangeColor(for: colorScheme))
                    .help("Revert all changes to this book")
                }

                Spacer()
                Button("Manage Editions") {
                    showsManageEditions = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Manage editions")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .sheet(isPresented: $showsManageEditions) {
            ManageEditionsWindow()
        }
    }

    @ViewBuilder
    private func scopeContent(bookId: String) -> some View {
        switch selectedScope {
            case .work:
                WorkMetadataLayout(
                    bookId: bookId,
                    viewModel: viewModel,
                    openHardcoverImport: openHardcoverImport,
                )
            case .audiobook:
                EditionMetadataLayout(
                    bookId: bookId,
                    viewModel: viewModel,
                    scope: .audiobook,
                    selectedCoverScope: $selectedCoverScope,
                    openHardcoverImport: openHardcoverImport,
                )
            case .ebook:
                EditionMetadataLayout(
                    bookId: bookId,
                    viewModel: viewModel,
                    scope: .ebook,
                    selectedCoverScope: $selectedCoverScope,
                    openHardcoverImport: openHardcoverImport,
                )
        }
    }
}

private struct ManageEditionsWindow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsUnsupported = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Editions")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                editionRow(title: "Audiobook Edition", systemImage: "headphones")
                editionRow(title: "Ebook Edition", systemImage: "book")

                HStack {
                    Button {
                        showsUnsupported = true
                    } label: {
                        Label("Add Edition", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .frame(width: 380)
        .alert("Not supported by Storyteller yet", isPresented: $showsUnsupported) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Adding or removing editions is not supported by Storyteller yet.")
        }
    }

    private func editionRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Button {
                showsUnsupported = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .help("Edit edition")
            Spacer()
            Button {
                showsUnsupported = true
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Remove edition")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .metadataEditorBoundary()
    }
}
