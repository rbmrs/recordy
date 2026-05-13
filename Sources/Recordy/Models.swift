import CoreGraphics
import Foundation

enum RecordingFPS: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) FPS" }
}

enum QualityProfile: String, CaseIterable, Identifiable {
    case original
    case balanced
    case low
    case tiny

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original:
            "Original"
        case .balanced:
            "Balanced"
        case .low:
            "Low"
        case .tiny:
            "Tiny"
        }
    }

    var outputScale: Double {
        switch self {
        case .original:
            1.0
        case .balanced:
            0.85
        case .low:
            0.7
        case .tiny:
            0.5
        }
    }

    var maxVideoBitRate: Int {
        switch self {
        case .original:
            18_000_000
        case .balanced:
            7_000_000
        case .low:
            3_500_000
        case .tiny:
            1_800_000
        }
    }

    var minVideoBitRate: Int {
        switch self {
        case .original:
            2_500_000
        case .balanced:
            900_000
        case .low:
            550_000
        case .tiny:
            300_000
        }
    }

    var bitsPerPixelPerFrame: Double {
        switch self {
        case .original:
            0.11
        case .balanced:
            0.065
        case .low:
            0.04
        case .tiny:
            0.026
        }
    }

    func videoBitRate(width: Int, height: Int, fps: Int) -> Int {
        let estimated = Double(width * height * fps) * bitsPerPixelPerFrame
        return min(maxVideoBitRate, max(minVideoBitRate, Int(estimated.rounded())))
    }
}

struct RecordingSettings: Equatable {
    var fps: RecordingFPS = .fps30
    var quality: QualityProfile = .balanced
    var audioEnabled: Bool = false
}

struct CaptureRegion: Equatable {
    let screenRect: CGRect
    let displayID: CGDirectDisplayID
    let outputSize: CGSize
}

enum RecorderState: Equatable {
    case idle
    case preparing
    case recording(URL)
    case stopping
    case failed(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var label: String {
        switch self {
        case .idle:
            "Ready"
        case .preparing:
            "Preparing..."
        case .recording:
            "Recording"
        case .stopping:
            "Stopping..."
        case .failed(let message):
            message
        }
    }
}
