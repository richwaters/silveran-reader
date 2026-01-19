import SwiftUI
import UIKit

extension Notification.Name {
    static let appWillResignActive = Notification.Name("appWillResignActive")
}

struct SilveranReaderApp: App {
    @State private var mediaViewModel: MediaViewModel

    init() {
        let vm = MediaViewModel()
        _mediaViewModel = State(initialValue: vm)

        Task {
            do {
                if let credentials = try await AuthenticationActor.shared.loadCredentials() {
                    let _ = await StorytellerActor.shared.setLogin(
                        baseURL: credentials.url,
                        username: credentials.username,
                        password: credentials.password
                    )
                }
            } catch {
                debugLog(
                    "[SilveranReaderApp] Failed to load credentials: \(error.localizedDescription)"
                )
            }

            do {
                try await FilesystemActor.shared.copyWebResourcesFromBundle()
            } catch {
                debugLog(
                    "[SilveranReaderApp] Failed to copy web resources: \(error.localizedDescription)"
                )
            }

            await FilesystemActor.shared.cleanupExtractedEpubDirectories()

            await AppleWatchActor.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup("Library", id: "MyLibrary") {
            iOSLibraryView()
                .environment(mediaViewModel)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    handleDidEnterBackground()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    handleDidBecomeActive()
                }
                .task {
                    if UIApplication.shared.applicationState == .active {
                        handleDidBecomeActive()
                    }
                }
        }
    }

    private func handleDidEnterBackground() {
        debugLog(
            "[SilveranReaderApp] App entering background - posting resign notification"
        )
        NotificationCenter.default.post(name: .appWillResignActive, object: nil)
        Task {
            await StorytellerActor.shared.setActive(false, source: .app)
        }
    }

    private func handleDidBecomeActive() {
        debugLog("[SilveranReaderApp] App becoming active")
        Task {
            await StorytellerActor.shared.setActive(true, source: .app)
        }
    }
}
