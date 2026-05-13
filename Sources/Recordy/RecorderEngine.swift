import Foundation

protocol RecorderEngine: AnyObject, Sendable {
    var onStateChange: (@Sendable (RecorderState) -> Void)? { get set }

    func start(region: CaptureRegion, settings: RecordingSettings) async throws -> URL
    func stop() async throws -> URL
}

enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noDisplay
    case noRegion
    case writerSetupFailed
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already running."
        case .notRecording:
            "No recording is running."
        case .noDisplay:
            "Could not find the selected display."
        case .noRegion:
            "The capture region is too small."
        case .writerSetupFailed:
            "Could not prepare the movie writer."
        case .writerFailed(let message):
            message
        }
    }
}

final class WindowsRecorderEnginePlaceholder {
    // Future Windows support should implement RecorderEngine with Windows Graphics Capture.
}
