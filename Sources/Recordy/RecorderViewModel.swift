import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var settings = RecordingSettings()
    @Published var state: RecorderState = .idle
    @Published var lastRecordingURL: URL?
    @Published var settingsDropdownOpen = false

    var regionProvider: (() -> CaptureRegion?)?

    private let engine: RecorderEngine

    init(engine: RecorderEngine) {
        self.engine = engine
        self.engine.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.state = state
                if case .recording(let url) = state {
                    self?.lastRecordingURL = url
                }
            }
        }
    }

    func toggleRecording() {
        Task {
            do {
                if state.isRecording {
                    lastRecordingURL = try await engine.stop()
                } else {
                    guard let region = regionProvider?() else {
                        state = .failed(RecorderError.noRegion.localizedDescription)
                        return
                    }
                    lastRecordingURL = try await engine.start(region: region, settings: settings)
                }
            } catch {
                state = .failed(error.recordyDescription)
            }
        }
    }
}

private extension Error {
    var recordyDescription: String {
        let nsError = self as NSError
        return [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
            "\(nsError.domain) \(nsError.code)"
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
    }
}
