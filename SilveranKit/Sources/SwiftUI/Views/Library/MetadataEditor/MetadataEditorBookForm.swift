import SwiftUI

struct MetadataEditorBookForm: View {
    @Bindable var viewModel: MetadataEditorViewModel
    @Binding var selectedSection: MetadataEditorSection
    @Binding var selectedCoverScope: CoversTab.CoverScope
    let openHardcoverImport: () -> Void

    private var bookId: String? { viewModel.selectedBookId }

    var body: some View {
        Group {
            if let bookId {
                VStack(spacing: 0) {
                    if selectedSection == .covers {
                        Picker("", selection: $selectedCoverScope) {
                            ForEach(CoversTab.CoverScope.allCases) { scope in
                                Text(scope.rawValue.capitalized).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        Divider()
                    }

                    switch selectedSection {
                    case .titleDetails:
                        TitleDetailsTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            openHardcoverImport: openHardcoverImport
                        )
                    case .description:
                        DescriptionTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            openHardcoverImport: openHardcoverImport
                        )
                    case .authors:
                        CreatorsTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            scope: .authors,
                            openHardcoverImport: openHardcoverImport
                        )
                    case .narrators:
                        CreatorsTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            scope: .narrators,
                            openHardcoverImport: openHardcoverImport
                        )
                    case .otherCreators:
                        CreatorsTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            scope: .otherCreators,
                            openHardcoverImport: openHardcoverImport
                        )
                    case .organization:
                        OrganizationTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            openHardcoverImport: openHardcoverImport
                        )
                    case .covers:
                        CoversTab(
                            bookId: bookId,
                            viewModel: viewModel,
                            scope: selectedCoverScope,
                            openHardcoverImport: openHardcoverImport
                        )
                    }
                }
            } else {
                ContentUnavailableView("No Book Selected", systemImage: "book.closed")
            }
        }
    }
}
