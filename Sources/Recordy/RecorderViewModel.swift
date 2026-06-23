import AVFoundation
import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var settings = RecordingSettings() {
        didSet {
            if oldValue.camera != settings.camera {
                cameraSelectionChanged?(settings.camera)
            }
            if oldValue.aspectRatio != settings.aspectRatio {
                aspectRatioChanged?(settings.aspectRatio)
            }
            persistSettings()
        }
    }
    @Published var state: RecorderState = .idle
    @Published var lastRecordingURL: URL?
    @Published var settingsDropdownOpen = false
    @Published var microphoneOptions: [MicrophoneSource] = [.off]
    @Published var cameraOptions: [CameraSource] = [.off]
    @Published var cameraShape: CameraShape = .circle {
        didSet {
            cameraShapeChanged?(cameraShape)
            persistSettings()
        }
    }

    var regionProvider: (() -> CaptureRegion?)?
    var cameraSelectionChanged: ((CameraSource) -> Void)?
    var cameraShapeChanged: ((CameraShape) -> Void)?
    var aspectRatioChanged: ((CaptureAspectRatio) -> Void)?

    private let engine: RecorderEngine

    init(engine: RecorderEngine) {
        self.engine = engine
        restoreSettings()
        self.engine.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.state = state
                if case .recording(let url) = state {
                    self?.lastRecordingURL = url
                }
            }
        }
        refreshMicrophones()
        refreshCameras()
    }

    func syncCameraOverlay() {
        cameraSelectionChanged?(settings.camera)
        cameraShapeChanged?(cameraShape)
    }

    func syncCaptureWindowSettings() {
        aspectRatioChanged?(settings.aspectRatio)
    }

    private func restoreSettings() {
        let persisted = AppPreferences.loadSettings()

        settings.fps = RecordingFPS(rawValue: persisted.fps) ?? .fps30
        settings.quality = QualityProfile(rawValue: persisted.quality) ?? .balanced
        settings.aspectRatio = CaptureAspectRatio(rawValue: persisted.aspectRatio) ?? .free
        settings.systemAudio = SystemAudioSource(rawValue: persisted.systemAudio) ?? .off
        settings.audioTrackMode = AudioTrackMode(rawValue: persisted.audioTrackMode) ?? .mixed

        if let microphoneID = persisted.microphoneID {
            settings.microphone = .device(
                id: microphoneID,
                label: persisted.microphoneLabel ?? "Microphone"
            )
        }

        if let cameraID = persisted.cameraID {
            settings.camera = .device(
                id: cameraID,
                label: persisted.cameraLabel ?? "Camera"
            )
        }

        cameraShape = CameraShape(rawValue: persisted.cameraShape) ?? .circle
    }

    private func persistSettings() {
        AppPreferences.save(settings: settings, cameraShape: cameraShape)
    }

    func refreshMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        var seenDeviceIDs = Set<String>()
        let devices = session.devices.compactMap { device -> MicrophoneSource? in
            guard seenDeviceIDs.insert(device.uniqueID).inserted else {
                return nil
            }
            return .device(id: device.uniqueID, label: device.localizedName)
        }

        microphoneOptions = [.off] + devices

        if let selectedDeviceID = settings.microphone.deviceID,
           let refreshedSelection = microphoneOptions.first(where: { $0.deviceID == selectedDeviceID }) {
            settings.microphone = refreshedSelection
        } else if !microphoneOptions.contains(settings.microphone) {
            settings.microphone = .off
        }
    }

    func refreshCameras() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )

        var seenDeviceIDs = Set<String>()
        let devices = session.devices.compactMap { device -> CameraSource? in
            guard seenDeviceIDs.insert(device.uniqueID).inserted else {
                return nil
            }
            return .device(id: device.uniqueID, label: device.localizedName)
        }

        cameraOptions = [.off] + devices

        if let selectedDeviceID = settings.camera.deviceID,
           let refreshedSelection = cameraOptions.first(where: { $0.deviceID == selectedDeviceID }) {
            settings.camera = refreshedSelection
        } else if !cameraOptions.contains(settings.camera) {
            settings.camera = .off
        }
    }

    func toggleCameraShape() {
        cameraShape = cameraShape == .circle ? .square : .circle
    }

    func toggleRecording() {
        Task {
            do {
                if state.isRecording {
                    lastRecordingURL = try await engine.stop()
                } else {
                    refreshMicrophones()
                    refreshCameras()
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
