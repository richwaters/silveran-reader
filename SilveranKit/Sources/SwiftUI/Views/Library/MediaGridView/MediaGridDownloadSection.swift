import SwiftUI

struct MediaGridDownloadSection: View {
    let item: BookMetadata
    @Environment(MediaViewModel.self) private var mediaViewModel
    #if os(macOS)
    @State private var showServerMediaManagement = false
    #endif

    var body: some View {
        let options = MediaGridViewUtilities.mediaDownloadOptions(for: item)
        Group {
            if options.isEmpty {
                EmptyView()
            } else {
                content(with: options)
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showServerMediaManagement) {
            ServerMediaManagementView(item: item)
                .environment(mediaViewModel)
        }
        #endif
    }

    private var isServerBook: Bool {
        mediaViewModel.isServerBook(item.id)
    }

    @ViewBuilder
    private func content(with options: [MediaDownloadOption]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available Media")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                #if os(macOS)
                if isServerBook {
                    Button("Manage...") {
                        showServerMediaManagement = true
                    }
                    .font(.callout)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                #endif
            }

            MediaDownloadOptionsList(item: item, options: options)
        }
    }
}
