import Foundation
import StoryAlignCore

public final class ReadaloudProgressUpdater: ProgressUpdater, @unchecked Sendable {
    public let updateQueue: DispatchQueue

    private let lock = NSLock()
    private var _stageProgress: [ProcessingStage: Double] = [:]
    private var _stageTotal: [ProcessingStage: Double] = [:]
    private var _currentStage: ProcessingStage = .epub
    private var _currentMessage: String = ""
    private var _overallProgress: Double = 0.0

    private let onUpdate: @Sendable (ProcessingStage, String, Double) -> Void

    public init(onUpdate: @escaping @Sendable (ProcessingStage, String, Double) -> Void) {
        self.updateQueue = DispatchQueue(label: "com.silveran.readaloud.progress")
        self.onUpdate = onUpdate
    }

    public var stageProgress: [ProcessingStage: Double] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _stageProgress
        }
        set {
            lock.lock()
            _stageProgress = newValue
            lock.unlock()
        }
    }

    public var stageTotal: [ProcessingStage: Double] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _stageTotal
        }
        set {
            lock.lock()
            _stageTotal = newValue
            lock.unlock()
        }
    }

    public var currentStage: ProcessingStage {
        lock.lock()
        defer { lock.unlock() }
        return _currentStage
    }

    public var currentMessage: String {
        lock.lock()
        defer { lock.unlock() }
        return _currentMessage
    }

    public var overallProgress: Double {
        lock.lock()
        defer { lock.unlock() }
        return _overallProgress
    }

    public func show(
        stageProgress: Double,
        stageTotal: Double,
        overallCompletionPercent: Double,
        msgPregix: String,
        unit: ProgressUpdaterUnit
    ) {
        let stage: ProcessingStage
        let message: String
        let progress: Double

        lock.lock()
        for orderedStage in ProcessingStage.orderedCases {
            if (_stageProgress[orderedStage] ?? 0) < (_stageTotal[orderedStage] ?? 0) {
                _currentStage = orderedStage
                break
            }
            if (_stageTotal[orderedStage] ?? 0) == 0 && orderedStage != .all {
                _currentStage = orderedStage
                break
            }
        }
        _currentMessage = msgPregix
        _overallProgress = overallCompletionPercent / 100.0
        stage = _currentStage
        message = _currentMessage
        progress = _overallProgress
        lock.unlock()

        onUpdate(stage, message, progress)
    }
}

extension ProcessingStage {
    var displayName: String {
        switch self {
            case .epub: return "Parsing EPUB"
            case .audio: return "Processing Audio"
            case .transcribe: return "Transcribing"
            case .align: return "Aligning"
            case .xml: return "Generating SMIL"
            case .export: return "Exporting"
            case .report: return "Creating Report"
            case .all: return "Processing"
        }
    }
}
