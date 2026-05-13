@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class MacScreenCaptureRecorder: NSObject, @unchecked Sendable, RecorderEngine {
    var onStateChange: (@Sendable (RecorderState) -> Void)?

    private let sampleQueue = DispatchQueue(label: "recordy.capture.samples")
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var finishing = false

    func start(region: CaptureRegion, settings: RecordingSettings) async throws -> URL {
        guard stream == nil else {
            throw RecorderError.alreadyRecording
        }

        emit(.preparing)

        let outputURL = try makeOutputURL()
        let writer = try makeWriter(outputURL: outputURL, region: region, settings: settings)

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = shareableContent.displays.first(where: { $0.displayID == region.displayID }) else {
            throw RecorderError.noDisplay
        }

        let currentProcessID = Int32(ProcessInfo.processInfo.processIdentifier)
        let excludedWindows = shareableContent.windows.filter { window in
            window.owningApplication?.processID == currentProcessID
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let configuration = makeStreamConfiguration(region: region, settings: settings)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if settings.audioEnabled {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }

            self.stream = stream
            self.assetWriter = writer
            self.outputURL = outputURL
            self.sessionStarted = false
            self.finishing = false

            try await stream.startCapture()
        } catch {
            cleanupAfterStartFailure(writer: writer, error: error)
            throw error
        }

        emit(.recording(outputURL))
        return outputURL
    }

    func stop() async throws -> URL {
        guard let stream else {
            throw RecorderError.notRecording
        }

        emit(.stopping)
        try await stream.stopCapture()

        return try await withCheckedThrowingContinuation { continuation in
            sampleQueue.async {
                self.finishWriting(continuation: continuation)
            }
        }
    }

    private func makeStreamConfiguration(region: CaptureRegion, settings: RecordingSettings) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int(region.outputSize.width))
        configuration.height = max(2, Int(region.outputSize.height))
        configuration.sourceRect = region.screenRect
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = true
        configuration.queueDepth = 5
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(settings.fps.rawValue)
        )
        configuration.capturesAudio = settings.audioEnabled
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        return configuration
    }

    private func makeWriter(
        outputURL: URL,
        region: CaptureRegion,
        settings: RecordingSettings
    ) throws -> AVAssetWriter {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let width = max(2, Int(region.outputSize.width))
        let height = max(2, Int(region.outputSize.height))
        let bitsPerSecond = settings.quality.videoBitRate(
            width: width,
            height: height,
            fps: settings.fps.rawValue
        )

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: settings.fps.rawValue,
                AVVideoMaxKeyFrameIntervalKey: settings.fps.rawValue * 2,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerSetupFailed
        }
        writer.add(videoInput)
        self.videoInput = videoInput

        if settings.audioEnabled {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true

            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
            }
        }

        return writer
    }

    private func makeOutputURL() throws -> URL {
        let fileManager = FileManager.default
        let moviesURL = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Movies")
        let folderURL = moviesURL.appending(path: "Recordy", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "\(formatter.string(from: Date())).mp4"
        return folderURL.appending(path: filename)
    }

    private func finishWriting(
        continuation: CheckedContinuation<URL, Error>
    ) {
        guard !finishing else {
            continuation.resume(throwing: RecorderError.notRecording)
            return
        }
        finishing = true

        let writer = assetWriter
        let finalURL = outputURL

        stream = nil
        assetWriter = nil
        outputURL = nil

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        videoInput = nil
        audioInput = nil
        sessionStarted = false

        guard let writer, let finalURL else {
            emit(.idle)
            continuation.resume(throwing: RecorderError.writerSetupFailed)
            return
        }

        if writer.status == .unknown {
            writer.cancelWriting()
            emit(.idle)
            continuation.resume(returning: finalURL)
            return
        }

        let writerBox = SendableWriterBox(writer)
        writer.finishWriting {
            let writer = writerBox.writer
            if let error = writer.error {
                self.emit(.failed(error.localizedDescription))
                continuation.resume(throwing: error)
            } else {
                self.emit(.idle)
                continuation.resume(returning: finalURL)
            }
        }
    }

    private func cleanupAfterStartFailure(writer: AVAssetWriter, error: Error) {
        stream = nil
        assetWriter = nil
        outputURL = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false
        finishing = false
        writer.cancelWriting()
        emit(.failed(error.localizedDescription))
    }

    private func emit(_ state: RecorderState) {
        DispatchQueue.main.async {
            self.onStateChange?(state)
        }
    }
}

private final class SendableWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

extension MacScreenCaptureRecorder: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              !finishing,
              let writer = assetWriter else {
            return
        }

        if writer.status == .failed {
            emit(.failed(writer.error?.localizedDescription ?? "Recording failed."))
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            guard writer.startWriting() else {
                emit(.failed(writer.error?.localizedDescription ?? "Could not start writing."))
                return
            }
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        switch type {
        case .screen:
            guard let videoInput, videoInput.isReadyForMoreMediaData else {
                return
            }
            videoInput.append(sampleBuffer)
        case .audio:
            guard let audioInput, audioInput.isReadyForMoreMediaData else {
                return
            }
            audioInput.append(sampleBuffer)
        case .microphone:
            return
        @unknown default:
            return
        }
    }
}

extension MacScreenCaptureRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        emit(.failed(error.localizedDescription))
    }
}
