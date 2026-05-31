import Foundation
import SilveranKitCommon
import SwiftUI

@MainActor
@Observable
public final class TVSettingsViewModel {
    var storytellerSources: [BookSourceRecord] = []
    var selectedSourceID: BookSourceID?
    var serverURL: String = ""
    var username: String = ""
    var password: String = ""
    var connectionError: String?
    var isTesting: Bool = false
    var connectionStatus: ConnectionStatus = .disconnected

    init() {
        Task {
            await loadSources()
        }
    }

    var selectedSourceName: String {
        storytellerSources.first { $0.id == selectedSourceID }?.name
            ?? BookSourceKind.storyteller.defaultName
    }

    func loadSources() async {
        storytellerSources = await BookServiceActor.shared.bookSources
            .filter { $0.kind == .storyteller }
        if selectedSourceID == nil || !storytellerSources.contains(where: { $0.id == selectedSourceID }) {
            selectedSourceID = storytellerSources.first?.id
        }
        await loadCredentialsForSelectedSource()
    }

    func loadCredentialsForSelectedSource() async {
        guard let selectedSourceID else {
            serverURL = ""
            username = ""
            password = ""
            connectionStatus = .disconnected
            return
        }

        do {
            if let credentials = try await AuthenticationActor.shared.loadCredentials(
                sourceID: selectedSourceID,
            ) {
                serverURL = credentials.url
                username = credentials.username
                password = credentials.password
            } else {
                serverURL = ""
                username = ""
                password = ""
            }
            connectionStatus = await BookServiceActor.shared.connectionStatus(
                sourceID: selectedSourceID,
            )
        } catch {
            debugLog("[TVSettingsViewModel] Failed to load credentials: \(error)")
        }
    }

    func testConnection() async {
        isTesting = true
        connectionError = nil

        let success: Bool
        if let selectedSourceID {
            success = await BookServiceActor.shared.setLogin(
                sourceID: selectedSourceID,
                baseURL: serverURL,
                username: username,
                password: password,
            )
        } else {
            success = false
        }

        if success {
            connectionError = nil
            connectionStatus = .connected
            await saveCredentials()
        } else {
            connectionStatus = .error("Login failed")
            connectionError = "Failed to connect. Check your credentials."
        }

        isTesting = false
    }

    func saveCredentials() async {
        guard let selectedSourceID else { return }
        do {
            try await AuthenticationActor.shared.saveCredentials(
                url: serverURL,
                username: username,
                password: password,
                sourceID: selectedSourceID,
            )
            debugLog("[TVSettingsViewModel] Credentials saved")
        } catch {
            debugLog("[TVSettingsViewModel] Failed to save credentials: \(error)")
        }
    }

    func logout() async {
        guard let selectedSourceID else { return }
        do {
            try await AuthenticationActor.shared.deleteCredentials(sourceID: selectedSourceID)
            serverURL = ""
            username = ""
            password = ""
            connectionStatus = .disconnected
            _ = await BookServiceActor.shared.logout(sourceID: selectedSourceID)
            debugLog("[TVSettingsViewModel] Logged out")
        } catch {
            debugLog("[TVSettingsViewModel] Failed to logout: \(error)")
        }
    }
}
