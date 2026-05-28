import SwiftUI
import UniformTypeIdentifiers

public struct StorytellerServerSettingsView: View {
    @State private var sources: [BookSourceRecord] = []
    @State private var sourceURLs: [BookSourceID: String] = [:]
    @State private var isLoading = false
    @State private var showingAddServer = false

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init() {}

    public var body: some View {
        Form {
            Section("Servers") {
                if isLoading && sources.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading Servers")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sources) { source in
                        NavigationLink {
                            BookSourceEditorView(source: source) {
                                await loadSources()
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                    Text(sourceDetail(for: source))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } icon: {
                                Image(systemName: iconName(for: source.kind))
                            }
                        }
                    }
                }

                Button {
                    showingAddServer = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            }

            #if os(macOS)
            Section {
                Button("Upload New Book to Server...") {
                    openWindow(id: "UploadNewBook", value: UploadNewBookData())
                }
            } header: {
                Text("Upload")
            } footer: {
                Text("Choose the destination server in the upload window.")
            }
            #endif
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .modifier(SoftScrollEdgeModifier())
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, alignment: .center)
        .navigationTitle("Servers")
        .task {
            await loadSources()
        }
        .sheet(isPresented: $showingAddServer) {
            NavigationStack {
                BookSourceEditorView(source: nil) {
                    await loadSources()
                    await MainActor.run {
                        showingAddServer = false
                    }
                }
            }
        }
    }

    private func loadSources() async {
        await MainActor.run {
            isLoading = true
        }
        let loadedSources = await BookServiceActor.shared.bookSources
        var urls: [BookSourceID: String] = [:]
        for source in loadedSources where source.kind == .storyteller {
            if let credentials = await BookServiceActor.shared.credentials(for: source.id) {
                urls[source.id] = credentials.url
            }
        }
        await MainActor.run {
            sources = loadedSources
            sourceURLs = urls
            isLoading = false
        }
    }

    private func sourceDetail(for source: BookSourceRecord) -> String {
        switch source.kind {
            case .storyteller:
                return sourceURLs[source.id] ?? "No URL saved"
            case .localFolder:
                return source.storagePath ?? "No folder selected"
        }
    }

    private func iconName(for kind: BookSourceKind) -> String {
        switch kind {
            case .storyteller:
                return "server.rack"
            case .localFolder:
                return "folder"
        }
    }
}

private struct BookSourceEditorView: View {
    let source: BookSourceRecord?
    let onSaved: () async -> Void

    @State private var kind: BookSourceKind = .storyteller
    @State private var name = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var folderPath = ""
    @State private var folderBookmarkData: Data?
    @State private var hasLoadedCredentials = false
    @State private var hasSavedCredentials = false
    @State private var isLoading = false
    @State private var isPasswordVisible = false
    @State private var showingFolderImporter = false
    @State private var connectionStatus: ConnectionTestStatus = .notTested
    @State private var showRemoveDataConfirmation = false

    @Environment(\.dismiss) private var dismiss

    private enum ConnectionTestStatus: Equatable {
        case notTested
        case testing
        case success
        case failure(String)
    }

    private var sourceID: BookSourceID? {
        source?.id
    }

    private var isExistingSource: Bool {
        source != nil
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isLoading else {
            return false
        }
        switch kind {
            case .storyteller:
                return !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !password.isEmpty
            case .localFolder:
                return !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Form {
            Section("Server Configuration") {
                Picker("Type", selection: $kind) {
                    Text(BookSourceKind.storyteller.displayName).tag(BookSourceKind.storyteller)
                    Text(BookSourceKind.localFolder.displayName).tag(BookSourceKind.localFolder)
                }
                .disabled(isExistingSource)

                TextField("Name", text: $name)
                    .textContentType(.name)

                switch kind {
                    case .storyteller:
                        TextField("Server URL", text: $serverURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .help("e.g., https://storyteller.example.com")

                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        HStack {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                            }

                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isPasswordVisible ? "Hide password" : "Show password")
                        }
                    case .localFolder:
                        HStack {
                            TextField("Folder", text: $folderPath)
                                .textContentType(.URL)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button {
                                showingFolderImporter = true
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Choose folder")
                        }
                        .fileImporter(
                            isPresented: $showingFolderImporter,
                            allowedContentTypes: [.folder],
                            allowsMultipleSelection: false,
                        ) { result in
                            if case .success(let urls) = result, let url = urls.first {
                                setFolderURL(url)
                            }
                        }
                }
            }

            Section {
                HStack {
                    Button(primaryActionTitle) {
                        Task {
                            await saveSource()
                        }
                    }
                    .disabled(!canSave)

                    Spacer()

                    connectionStatusView
                }

                if isExistingSource && hasSavedCredentials {
                    Button(role: .destructive) {
                        showRemoveDataConfirmation = true
                    } label: {
                        Label("Remove Server", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(isLoading)
                }
            }

            if case .failure(let message) = connectionStatus {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        failureMessage(message)
                    }
                }
            }

            if let sourceID {
                Section("Details") {
                    LabeledContent("Source ID", value: sourceID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .modifier(SoftScrollEdgeModifier())
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, alignment: .center)
        .navigationTitle(isExistingSource ? name : "Add Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !isExistingSource {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove this server?",
            isPresented: $showRemoveDataConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Remove Server", role: .destructive) {
                Task {
                    await removeServer()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will delete saved credentials, cached metadata, downloaded media, and covers for books from this server."
            )
        }
        .task {
            await loadExistingSource()
        }
    }

    private var primaryActionTitle: String {
        switch kind {
            case .storyteller:
                return isExistingSource ? "Save Credentials and Connect" : "Add and Connect"
            case .localFolder:
                return isExistingSource ? "Save Folder Source" : "Add Folder Source"
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
            case .notTested:
                if hasSavedCredentials {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Text("Saved")
                            .foregroundStyle(.secondary)
                    }
                }
            case .testing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected")
                        .foregroundStyle(.secondary)
                }
            case .failure:
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Failed")
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func failureMessage(_ message: String) -> some View {
        if message.lowercased().contains("credentials") {
            Text("Invalid username or password. Please check your credentials and try again.")
                .font(.body)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.body)
                Text("If you just allowed local network access, try connecting again.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadExistingCredentials() async {
        await loadExistingSource()
    }

    private func loadExistingSource() async {
        guard !hasLoadedCredentials else { return }
        hasLoadedCredentials = true

        await MainActor.run {
            kind = source?.kind ?? .storyteller
            name = source?.name ?? ""
            folderPath = source?.storagePath ?? ""
            folderBookmarkData = source?.storageBookmarkData
        }

        guard let sourceID, source?.kind == .storyteller else { return }

        if let credentials = await BookServiceActor.shared.credentials(for: sourceID) {
            await MainActor.run {
                serverURL = credentials.url
                username = credentials.username
                password = credentials.password
                hasSavedCredentials = true
            }
        } else {
            await MainActor.run {
                hasSavedCredentials = false
            }
        }
    }

    private func saveSource() async {
        await MainActor.run {
            isLoading = true
            connectionStatus = .testing
        }

        let configuration = BookSourceConfiguration(
            kind: kind,
            name: name,
            serverURL: serverURL,
            username: username,
            password: password,
            storagePath: folderPath,
            storageBookmarkData: folderBookmarkData,
        )
        let success: Bool
        if let sourceID {
            success = await BookServiceActor.shared.updateBookSource(
                id: sourceID,
                configuration: configuration,
            )
        } else {
            let record = await BookServiceActor.shared.createBookSource(configuration)
            success = record != nil
        }

        if success {
            await onSaved()
            await MainActor.run {
                hasSavedCredentials = true
                isLoading = false
                connectionStatus = kind == .storyteller ? .success : .notTested
            }
        } else {
            let message = await failureMessageForCurrentSource()
            await MainActor.run {
                isLoading = false
                connectionStatus = .failure(message)
            }
        }
    }

    private func removeServer() async {
        guard let sourceID else { return }

        await MainActor.run {
            isLoading = true
        }

        let success = await BookServiceActor.shared.removeBookSource(id: sourceID)
        if success {
            await onSaved()
            await MainActor.run {
                isLoading = false
                dismiss()
            }
        } else {
            await MainActor.run {
                isLoading = false
                connectionStatus = .failure("Failed to remove server.")
            }
        }
    }

    private func failureMessageForCurrentSource() async -> String {
        guard let sourceID else { return "Connection failed." }
        let storytellerStatus = await BookServiceActor.shared.connectionStatus(sourceID: sourceID)
        if case .error(let message) = storytellerStatus {
            return message
        }
        return "Connection failed."
    }

    private func setFolderURL(_ url: URL) {
        folderPath = url.path
        #if os(macOS)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        folderBookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        )
        #elseif os(iOS)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        folderBookmarkData = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        )
        #else
        folderBookmarkData = nil
        #endif
    }
}
