import SwiftUI

struct MetadataEditorBookForm: View {
    @Bindable var viewModel: MetadataEditorViewModel
    @State private var selectedTab: MetadataEditorTab = .titleDetails

    private var bookId: String? { viewModel.selectedBookId }

    var body: some View {
        if let bookId {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(MetadataEditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                switch selectedTab {
                case .titleDetails:
                    TitleDetailsTab(bookId: bookId, viewModel: viewModel)
                case .description:
                    DescriptionTab(bookId: bookId, viewModel: viewModel)
                case .creators:
                    CreatorsTab(bookId: bookId, viewModel: viewModel)
                case .organization:
                    OrganizationTab(bookId: bookId, viewModel: viewModel)
                case .covers:
                    CoversTab()
                }
            }
        } else {
            ContentUnavailableView("No Book Selected", systemImage: "book.closed")
        }
    }
}
