import AppKit
import Foundation

enum AppPreferences {
    private static let settingsKey = "recordy.settings.v1"
    private static let captureFrameKey = "recordy.captureFrame.v1"
    private static let cameraFrameKey = "recordy.cameraFrame.v1"
    private static let cameraRelativeFrameKey = "recordy.cameraRelativeFrame.v1"
    private static let automaticUpdatesKey = "recordy.autoUpdate.v1"
    private static let lastUpdateCheckKey = "recordy.lastUpdateCheck.v1"

    static var automaticUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: automaticUpdatesKey) }
        set { UserDefaults.standard.set(newValue, forKey: automaticUpdatesKey) }
    }

    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastUpdateCheckKey) }
    }

    static func loadSettings() -> PersistedSettings {
        guard let data = UserDefaults.standard.dictionary(forKey: settingsKey) else {
            return .defaults
        }

        return PersistedSettings(
            fps: data["fps"] as? Int ?? PersistedSettings.defaults.fps,
            quality: data["quality"] as? String ?? PersistedSettings.defaults.quality,
            aspectRatio: data["aspectRatio"] as? String ?? PersistedSettings.defaults.aspectRatio,
            systemAudio: data["systemAudio"] as? String ?? PersistedSettings.defaults.systemAudio,
            audioTrackMode: data["audioTrackMode"] as? String ?? PersistedSettings.defaults.audioTrackMode,
            microphoneID: data["microphoneID"] as? String,
            microphoneLabel: data["microphoneLabel"] as? String,
            cameraID: data["cameraID"] as? String,
            cameraLabel: data["cameraLabel"] as? String,
            cameraShape: data["cameraShape"] as? String ?? PersistedSettings.defaults.cameraShape,
            cameraSize: data["cameraSize"] as? String ?? PersistedSettings.defaults.cameraSize
        )
    }

    static func save(settings: RecordingSettings, cameraShape: CameraShape, cameraSize: CameraSize) {
        var data: [String: Any] = [
            "fps": settings.fps.rawValue,
            "quality": settings.quality.rawValue,
            "aspectRatio": settings.aspectRatio.rawValue,
            "systemAudio": settings.systemAudio.rawValue,
            "audioTrackMode": settings.audioTrackMode.rawValue,
            "cameraShape": cameraShape.rawValue,
            "cameraSize": cameraSize.rawValue
        ]

        if let microphoneID = settings.microphone.deviceID {
            data["microphoneID"] = microphoneID
            data["microphoneLabel"] = settings.microphone.label
        }

        if let cameraID = settings.camera.deviceID {
            data["cameraID"] = cameraID
            data["cameraLabel"] = settings.camera.label
        }

        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    static func loadCaptureFrame() -> NSRect? {
        loadRect(forKey: captureFrameKey, minimumSize: CaptureLayout.minimumWindowSize)
    }

    static func saveCaptureFrame(_ frame: NSRect) {
        saveRect(frame, forKey: captureFrameKey)
    }

    static func loadCameraFrame() -> NSRect? {
        loadRect(forKey: cameraFrameKey, minimumSize: NSSize(width: 96, height: 96))
    }

    static func saveCameraFrame(_ frame: NSRect) {
        saveRect(frame, forKey: cameraFrameKey)
    }

    static func loadCameraRelativeFrame() -> NSRect? {
        loadRectWithoutScreenValidation(forKey: cameraRelativeFrameKey, minimumSize: NSSize(width: 96, height: 96))
    }

    static func saveCameraRelativeFrame(_ frame: NSRect) {
        saveRect(frame, forKey: cameraRelativeFrameKey)
    }

    private static func loadRect(forKey key: String, minimumSize: NSSize) -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        let rect = NSRectFromString(value)
        guard rect.width >= minimumSize.width,
              rect.height >= minimumSize.height,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              isVisibleOnAnyScreen(rect) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return rect
    }

    private static func saveRect(_ rect: NSRect, forKey key: String) {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0 else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(rect), forKey: key)
    }

    private static func loadRectWithoutScreenValidation(forKey key: String, minimumSize: NSSize) -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        let rect = NSRectFromString(value)
        guard rect.width >= minimumSize.width,
              rect.height >= minimumSize.height,
              rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return rect
    }

    private static func isVisibleOnAnyScreen(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = screen.visibleFrame.intersection(rect)
            return !intersection.isNull
                && intersection.width >= 80
                && intersection.height >= 80
        }
    }
}
