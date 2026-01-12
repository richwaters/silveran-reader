import Foundation
import StoryAlignCore
import SilveranKitCommon
import ZIPFoundation

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void
    private let completionHandler: @Sendable (URL?, Error?) -> Void
    var retainedSession: URLSession?

    init(
        progressHandler: @escaping @Sendable (Double) -> Void,
        completionHandler: @escaping @Sendable (URL?, Error?) -> Void
    ) {
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let pct = Int(progress * 100)
            if pct % 5 == 0 {
                debugLog("[ReadaloudGenerator] Download progress: \(pct)% (\(totalBytesWritten / 1_000_000)MB / \(totalBytesExpectedToWrite / 1_000_000)MB)")
            }
            progressHandler(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
            completionHandler(tempFile, nil)
        } catch {
            completionHandler(nil, error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            completionHandler(nil, error)
        }
    }
}

public enum ReadaloudGeneratorState: Equatable {
    case idle
    case processing
    case downloading(Double)
    case completed(URL)
    case error(String)
}

public enum WhisperModelSize: String, CaseIterable, Identifiable, Sendable {
    case tiny = "tiny.en"
    case base = "base.en"
    case small = "small.en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (fastest, ~75MB)"
        case .base: return "Base (balanced, ~142MB)"
        case .small: return "Small (best quality, ~466MB)"
        }
    }

    var binFileName: String { "ggml-\(rawValue).bin" }
    var mlmodelFileName: String { "ggml-\(rawValue)-encoder.mlmodelc" }

    var downloadURLs: [URL] {
        [
            // Hugging Face is much faster than GitHub releases
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(rawValue).bin")!,
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(rawValue)-encoder.mlmodelc.zip")!
        ]
    }
}

@Observable
@MainActor
public final class ReadaloudGeneratorViewModel {
    public var epubURL: URL?
    public var audioURL: URL?
    public var outputURL: URL?
    public var selectedModelSize: WhisperModelSize = .tiny
    public var selectedGranularity: Granularity = .sentence

    public private(set) var state: ReadaloudGeneratorState = .idle
    public private(set) var currentStage: ProcessingStage = .epub
    public private(set) var currentMessage: String = ""
    public private(set) var overallProgress: Double = 0.0
    public private(set) var logMessages: [(Date, LogLevel, String)] = []

    public private(set) var availableChapters: [(name: String, id: String)] = []
    public var startChapterIndex: Int? = nil
    public var endChapterIndex: Int? = nil

    private var alignmentTask: Task<Void, Never>?

    public init() {}

    public var canStart: Bool {
        epubURL != nil && audioURL != nil && outputURL != nil && state != .processing
    }

    public var isModelDownloaded: Bool {
        modelPath(for: selectedModelSize) != nil
    }

    public func loadChapters() {
        guard let epubURL else {
            availableChapters = []
            startChapterIndex = nil
            endChapterIndex = nil
            return
        }

        Task.detached { [weak self] in
            guard let self else { return }
            await self.parseChapters(from: epubURL)
        }
    }

    private nonisolated func parseChapters(from epubURL: URL) async {
        let access = epubURL.startAccessingSecurityScopedResource()
        defer { if access { epubURL.stopAccessingSecurityScopedResource() } }

        do {
            // Use SMILParser for proper chapter names (display)
            let sections = try SMILParser.parseEPUB(at: epubURL)

            // Also get StoryAlign's manifest IDs for filtering
            let logger = ReadaloudLogger(minLevel: .error)
            let sessionConfig = try SessionConfig(
                sessionDir: nil,
                modelFile: "/unused",
                runStage: .all,
                logger: logger,
                audioLoaderType: .avfoundation,
                throttle: false,
                progressUpdater: nil,
                toolName: "SilveranReader",
                version: "1.0",
                whisperBeamSize: nil,
                whisperDtw: false,
                reportType: .none,
                startChapter: nil,
                endChapter: nil,
                granularity: .sentence
            )
            defer { sessionConfig.cleanup() }

            let epub = try await EpubParser(sessionConfig: sessionConfig).parse(url: epubURL)
            let storyAlignItems = epub.manifest
                .sorted { $0.spineItemIndex < $1.spineItemIndex }
                .filter { $0.spineItemIndex >= 0 }

            // Combine: SMILParser labels for display, StoryAlign nameOrId for filtering
            let chapters = sections.enumerated().map { (index, section) in
                let displayName = section.label ?? "[Section \(index + 1)] (Unknown)"
                let filterId = index < storyAlignItems.count ? storyAlignItems[index].nameOrId : displayName
                return (name: displayName, id: filterId)
            }

            await MainActor.run {
                self.availableChapters = chapters
                self.startChapterIndex = nil
                self.endChapterIndex = nil
            }
        } catch {
            debugLog("[ReadaloudGenerator] Failed to parse chapters: \(error)")
            await MainActor.run {
                self.availableChapters = []
                self.startChapterIndex = nil
                self.endChapterIndex = nil
            }
        }
    }

    public func startAlignment() {
        guard canStart else { return }
        guard let epubURL, let audioURL, let outputURL else { return }

        state = .processing
        currentStage = .epub
        currentMessage = "Starting..."
        overallProgress = 0.0

        alignmentTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.runAlignment(epubURL: epubURL, audioURL: audioURL, outputURL: outputURL)
        }
    }

    public func cancel() {
        alignmentTask?.cancel()
        alignmentTask = nil
        state = .idle
    }

    public func downloadModel() {
        guard state != .processing else { return }

        debugLog("[ReadaloudGenerator] Starting model download for \(selectedModelSize.rawValue)")
        state = .downloading(0)
        let modelSize = selectedModelSize

        alignmentTask = Task.detached { [weak self] in
            await self?.downloadModelFiles(for: modelSize)
        }
    }

    private nonisolated func runAlignment(epubURL: URL, audioURL: URL, outputURL: URL) async {
        let modelPath: String? = await self.modelPath(for: selectedModelSize)
        let granularity = await self.selectedGranularity
        let chapters = await self.availableChapters
        let startIdx = await self.startChapterIndex
        let endIdx = await self.endChapterIndex

        let startChapter = startIdx.flatMap { chapters.indices.contains($0) ? chapters[$0].id : nil }
        let endChapter = endIdx.flatMap { chapters.indices.contains($0) ? chapters[$0].id : nil }

        guard let modelPath else {
            await MainActor.run { self.state = .error("Whisper model not found. Please download it first.") }
            return
        }

        // Start accessing security-scoped resources for sandboxed app
        let epubAccess = epubURL.startAccessingSecurityScopedResource()
        let audioAccess = audioURL.startAccessingSecurityScopedResource()
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer {
            if epubAccess { epubURL.stopAccessingSecurityScopedResource() }
            if audioAccess { audioURL.stopAccessingSecurityScopedResource() }
            if outputAccess { outputURL.stopAccessingSecurityScopedResource() }
        }

        let logger = ReadaloudLogger(minLevel: .info)
        let progressUpdater = ReadaloudProgressUpdater { [weak self] stage, message, progress in
            Task { @MainActor in
                self?.currentStage = stage
                self?.currentMessage = message
                self?.overallProgress = progress
            }
        }

        do {
            let sessionConfig = try SessionConfig(
                sessionDir: nil,
                modelFile: modelPath,
                runStage: .all,
                logger: logger,
                audioLoaderType: .avfoundation,
                throttle: false,
                progressUpdater: progressUpdater,
                toolName: "SilveranReader",
                version: "1.0",
                whisperBeamSize: nil,
                whisperDtw: false,
                reportType: .none,
                startChapter: startChapter,
                endChapter: endChapter,
                granularity: granularity
            )

            defer { sessionConfig.cleanup() }

            logger.log(.info, "Parsing ebook...")
            let epub = try await EpubParser(sessionConfig: sessionConfig).parse(url: epubURL)

            if Task.isCancelled {
                await MainActor.run { self.state = .idle }
                return
            }

            logger.log(.info, "Processing audio...")
            let audioBook = try await M4BParser(sessionConfig: sessionConfig).parse(
                url: audioURL,
                extractingInto: epub.opfURL.deletingLastPathComponent()
            )

            if Task.isCancelled {
                await MainActor.run { self.state = .idle }
                return
            }

            logger.log(.info, "Transcribing audio...")
            let transcriber = TranscriberFactory.transcriber(forSessionConfig: sessionConfig)
            let transcriptions = try await transcriber.transcribe(audioBook: audioBook, for: epub)

            if Task.isCancelled {
                await MainActor.run { self.state = .idle }
                return
            }

            logger.log(.info, "Aligning text to audio...")
            let alignedChapters = try await Aligner(sessionConfig: sessionConfig).align(
                ebook: epub,
                AudioBook: audioBook,
                rawTranscriptions: transcriptions
            )

            if Task.isCancelled {
                await MainActor.run { self.state = .idle }
                return
            }

            logger.log(.info, "Generating SMIL...")
            try await XMLUpdater(sessionConfig: sessionConfig).updateXml(
                forEbook: epub,
                audioBook: audioBook,
                alignedChapters: alignedChapters
            )

            if Task.isCancelled {
                await MainActor.run { self.state = .idle }
                return
            }

            logger.log(.info, "Exporting EPUB...")
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try EpubExporter(sessionConfig: sessionConfig).export(eBook: epub, to: outputURL)

            let messages = logger.messages
            await MainActor.run {
                self.logMessages = messages
                self.state = .completed(outputURL)
            }

        } catch {
            let messages = logger.messages
            let errorMessage = String(describing: error)
            await MainActor.run {
                self.logMessages = messages
                self.state = .error(errorMessage)
            }
        }
    }

    private nonisolated func downloadModelFiles(for modelSize: WhisperModelSize) async {
        debugLog("[ReadaloudGenerator] downloadModelFiles started for \(modelSize.rawValue)")
        let fm = FileManager.default
        let modelsDir = await modelsDirectory()
        debugLog("[ReadaloudGenerator] Models directory: \(modelsDir.path)")

        do {
            try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            debugLog("[ReadaloudGenerator] Created models directory")
        } catch {
            debugLog("[ReadaloudGenerator] Failed to create directory: \(error)")
            await MainActor.run { self.state = .error("Failed to create models directory: \(error.localizedDescription)") }
            return
        }

        let urls = modelSize.downloadURLs
        debugLog("[ReadaloudGenerator] Will download \(urls.count) files")

        for (index, url) in urls.enumerated() {
            debugLog("[ReadaloudGenerator] Processing file \(index + 1)/\(urls.count): \(url.lastPathComponent)")
            if Task.isCancelled {
                await MainActor.run { self.state = .idle }
                return
            }

            let targetURL = modelsDir.appendingPathComponent(url.lastPathComponent)

            if fm.fileExists(atPath: targetURL.path) {
                debugLog("[ReadaloudGenerator] File already exists, skipping")
                continue
            }

            let baseProgress = Double(index) / Double(urls.count)
            let fileWeight = 1.0 / Double(urls.count)

            do {
                debugLog("[ReadaloudGenerator] Starting download from \(url)")
                let localURL = try await downloadFile(from: url, baseProgress: baseProgress, fileWeight: fileWeight)
                debugLog("[ReadaloudGenerator] Download complete: \(url.lastPathComponent)")

                if url.pathExtension == "zip" {
                    try fm.unzipItem(at: localURL, to: modelsDir, overwrite: true)
                    try? fm.removeItem(at: localURL)
                } else {
                    if fm.fileExists(atPath: targetURL.path) {
                        try fm.removeItem(at: targetURL)
                    }
                    try fm.moveItem(at: localURL, to: targetURL)
                }

                let progress = Double(index + 1) / Double(urls.count)
                debugLog("[ReadaloudGenerator] File \(index + 1)/\(urls.count) done, progress: \(Int(progress * 100))%")
                await MainActor.run { self.state = .downloading(progress) }

            } catch {
                let errorMessage = error.localizedDescription
                debugLog("[ReadaloudGenerator] Download failed: \(errorMessage)")
                await MainActor.run { self.state = .error("Failed to download model: \(errorMessage)") }
                return
            }
        }

        debugLog("[ReadaloudGenerator] All downloads complete")
        await MainActor.run { self.state = .idle }
    }

    private nonisolated func downloadFile(from url: URL, baseProgress: Double, fileWeight: Double) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = ModelDownloadDelegate(
                progressHandler: { [weak self] fileProgress in
                    let totalProgress = baseProgress + (fileProgress * fileWeight)
                    Task { @MainActor in
                        self?.state = .downloading(totalProgress)
                    }
                },
                completionHandler: { downloadedURL, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let downloadedURL {
                        continuation.resume(returning: downloadedURL)
                    } else {
                        continuation.resume(throwing: NSError(domain: "ReadaloudGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
                    }
                }
            )

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.retainedSession = session
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    private func modelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SilveranReader/WhisperModels")
    }

    private func modelPath(for modelSize: WhisperModelSize) -> String? {
        let modelsDir = modelsDirectory()
        let binPath = modelsDir.appendingPathComponent(modelSize.binFileName)
        let mlmodelPath = modelsDir.appendingPathComponent(modelSize.mlmodelFileName)

        let fm = FileManager.default
        if fm.fileExists(atPath: binPath.path) && fm.fileExists(atPath: mlmodelPath.path) {
            return binPath.path
        }
        return nil
    }
}
