#if os(macOS)
import SwiftUI

struct BookContextMenuContent: View {
    let item: BookMetadata
    var onInfo: ((BookMetadata) -> Void)? = nil
    var onEditMetadata: (([String]) -> Void)? = nil
    @Environment(MediaViewModel.self) private var mediaViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let onInfo {
            Button {
                onInfo(item)
            } label: {
                Label("Show Book Information", systemImage: "info.circle")
            }
            Divider()
        }

        processingSection

        epubUpgradeSection

        deleteSection

        serverMediaSection

        if let onEditMetadata {
            Divider()
            Button {
                onEditMetadata([item.uuid])
            } label: {
                Label("Edit Metadata...", systemImage: "pencil")
            }
        }
    }

    @ViewBuilder
    private var processingSection: some View {
        let status = item.readaloud?.status?.uppercased() ?? ""
        let hasEbookAndAudio = item.hasAvailableEbook && item.hasAvailableAudiobook

        if status == "PROCESSING" || status == "QUEUED" {
            Button {
                Task {
                    _ = await StorytellerActor.shared.cancelAlignment(for: item.uuid)
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Cancel Processing", systemImage: "xmark.circle")
            }
        } else if status == "ALIGNED" {
            Button {
                Task {
                    _ = await StorytellerActor.shared.startAlignment(
                        for: item.uuid,
                        restart: .sync,
                    )
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Re-align (Fast)", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                Task {
                    _ = await StorytellerActor.shared.startAlignment(
                        for: item.uuid,
                        restart: .transcription,
                    )
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Re-transcribe & Align", systemImage: "waveform")
            }

            Button {
                Task {
                    _ = await StorytellerActor.shared.startAlignment(
                        for: item.uuid,
                        restart: .full,
                    )
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Full Reprocess", systemImage: "arrow.counterclockwise")
            }
        } else if status == "ERROR" || status == "STOPPED" {
            Button {
                Task {
                    _ = await StorytellerActor.shared.startAlignment(
                        for: item.uuid,
                        restart: .full,
                    )
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Retry Processing", systemImage: "arrow.counterclockwise")
            }

            Button {
                Task {
                    _ = await StorytellerActor.shared.startAlignment(
                        for: item.uuid,
                        restart: .sync,
                    )
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Re-align Only", systemImage: "arrow.triangle.2.circlepath")
            }
        } else if hasEbookAndAudio {
            Button {
                Task {
                    _ = await StorytellerActor.shared.startAlignment(for: item.uuid)
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Create Readaloud", systemImage: "text.bubble")
            }
        }
    }

    @ViewBuilder
    private var epubUpgradeSection: some View {
        if item.hasAvailableEbook {
            Divider()
            Button {
                Task {
                    _ = await StorytellerActor.shared.upgradeEpub(for: item.uuid)
                    await StorytellerActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Convert to EPUB 3", systemImage: "doc.badge.arrow.up")
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        let ebookDownloaded = mediaViewModel.isCategoryDownloaded(.ebook, for: item)
        let audioDownloaded = mediaViewModel.isCategoryDownloaded(.audio, for: item)
        let syncedDownloaded = mediaViewModel.isCategoryDownloaded(.synced, for: item)

        if ebookDownloaded || audioDownloaded || syncedDownloaded {
            Divider()

            if ebookDownloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: .ebook)
                } label: {
                    Label("Delete Local Ebook", systemImage: "trash")
                }
            }

            if audioDownloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: .audio)
                } label: {
                    Label("Delete Local Audiobook", systemImage: "trash")
                }
            }

            if syncedDownloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: .synced)
                } label: {
                    Label("Delete Local Readaloud", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var serverMediaSection: some View {
        if mediaViewModel.isServerBook(item.id) {
            Divider()
            Button {
                openWindow(
                    id: "ServerMediaManagement",
                    value: ServerMediaManagementData(bookId: item.id),
                )
            } label: {
                Label("Manage Server Media...", systemImage: "server.rack")
            }
        }
    }
}
#endif
