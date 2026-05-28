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
        }

        if let onEditMetadata {
            Button {
                onEditMetadata([item.uuid])
            } label: {
                Label("Edit Metadata...", systemImage: "pencil")
            }
        }

        deleteSection

        if hasServerActions {
            Divider()

            Menu {
                processingSection

                epubUpgradeSection

                serverMediaSection
            } label: {
                Label("Server Actions", systemImage: "server.rack")
            }
        }
    }

    private var hasServerActions: Bool {
        mediaViewModel.isServerBook(item.id)
    }

    private var hasProcessingActions: Bool {
        let status = item.readaloud?.status?.uppercased() ?? ""
        return status == "PROCESSING" || status == "QUEUED" || status == "ALIGNED"
            || status == "ERROR" || status == "STOPPED"
            || (item.hasAvailableEbook && item.hasAvailableAudiobook)
    }

    @ViewBuilder
    private var processingSection: some View {
        let status = item.readaloud?.status?.uppercased() ?? ""
        let hasEbookAndAudio = item.hasAvailableEbook && item.hasAvailableAudiobook

        if status == "PROCESSING" || status == "QUEUED" {
            Button {
                Task {
                    _ = await BookServiceActor.shared.cancelAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Cancel Processing", systemImage: "xmark.circle")
            }
        } else if status == "ALIGNED" {
            Button {
                Task {
                    _ = await BookServiceActor.shared.startAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                        restart: .sync,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Re-align (Fast)", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                Task {
                    _ = await BookServiceActor.shared.startAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                        restart: .transcription,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Re-transcribe & Align", systemImage: "waveform")
            }

            Button {
                Task {
                    _ = await BookServiceActor.shared.startAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                        restart: .full,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Full Reprocess", systemImage: "arrow.counterclockwise")
            }
        } else if status == "ERROR" || status == "STOPPED" {
            Button {
                Task {
                    _ = await BookServiceActor.shared.startAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                        restart: .full,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Retry Processing", systemImage: "arrow.counterclockwise")
            }

            Button {
                Task {
                    _ = await BookServiceActor.shared.startAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                        restart: .sync,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Re-align Only", systemImage: "arrow.triangle.2.circlepath")
            }
        } else if hasEbookAndAudio {
            Button {
                Task {
                    _ = await BookServiceActor.shared.startAlignment(
                        for: item.uuid,
                        sourceID: item.sourceID,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
                }
            } label: {
                Label("Create Readaloud", systemImage: "text.bubble")
            }
        }
    }

    @ViewBuilder
    private var epubUpgradeSection: some View {
        if item.canUpgradeToEpub3 {
            if hasProcessingActions {
                Divider()
            }
            Button {
                Task {
                    _ = await BookServiceActor.shared.upgradeEpub(
                        for: item.uuid,
                        sourceID: item.sourceID,
                    )
                    await BookServiceActor.shared.fetchLibraryInformation()
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
            if hasProcessingActions || item.canUpgradeToEpub3 {
                Divider()
            }
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
