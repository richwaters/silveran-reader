import SwiftUI

extension Notification.Name {
    static let appWillResignActive = Notification.Name("appWillResignActive")
}

struct SilveranReaderApp: App {
    @State private var mediaViewModel: MediaViewModel

    @Environment(\.scenePhase) private var scenePhase

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
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
            case .background:
                debugLog(
                    "[SilveranReaderApp] App entering background - posting resign notification"
                )
                NotificationCenter.default.post(name: .appWillResignActive, object: nil)
                Task {
                    await StorytellerActor.shared.setActive(false, source: .app)
                }

            case .active:
                debugLog("[SilveranReaderApp] App becoming active")
                Task {
                    await StorytellerActor.shared.setActive(true, source: .app)
                }

            case .inactive:
                break

            @unknown default:
                break
        }
    }
}
