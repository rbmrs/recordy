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
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var audioTrackMode: AudioTrackMode = .mixed
    private var sessionStarted = false
    private var finishing = false
    private var failed = false

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

        let excludedWindows = shareableContent.windows.filter { window in
            region.excludedWindowIDs.contains(window.windowID)
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let configuration = makeStreamConfiguration(region: region, settings: settings)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if settings.systemAudio.isEnabled {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            if settings.microphone.isEnabled {
                if #available(macOS 15.0, *) {
                    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
                } else {
                    throw RecorderError.writerFailed("Microphone capture requires macOS 15 or newer.")
                }
            }

            self.stream = stream
            self.assetWriter = writer
            self.outputURL = outputURL
            self.audioTrackMode = settings.audioTrackMode
            self.sessionStarted = false
            self.finishing = false
            self.failed = false

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
        configuration.capturesAudio = settings.systemAudio.isEnabled
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = settings.microphone.isEnabled
            configuration.microphoneCaptureDeviceID = settings.microphone.deviceID
        }
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

        if settings.systemAudio.isEnabled {
            systemAudioInput = try makeAudioInput(for: writer, label: "system audio")
        }

        if settings.microphone.isEnabled {
            microphoneInput = try makeAudioInput(for: writer, label: "microphone")
        }

        return writer
    }

    private func makeAudioInput(for writer: AVAssetWriter, label: String) throws -> AVAssetWriterInput {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(audioInput) else {
            throw RecorderError.writerFailed("Could not prepare the \(label) track.")
        }

        writer.add(audioInput)
        return audioInput
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
        let shouldMixAudioTracks = audioTrackMode == .mixed

        stream = nil
        assetWriter = nil
        outputURL = nil
        audioTrackMode = .mixed

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
        sessionStarted = false
        failed = false

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
                self.emit(.failed(error.recordyDescription))
                continuation.resume(throwing: error)
            } else if !shouldMixAudioTracks {
                self.emit(.idle)
                continuation.resume(returning: finalURL)
            } else {
                Task {
                    do {
                        let finalURL = try await Self.mixAudioTracksToSingleTrackIfNeeded(at: finalURL)
                        self.emit(.idle)
                        continuation.resume(returning: finalURL)
                    } catch {
                        self.emit(.failed("Saved recording, but audio mixdown failed: \(error.recordyDescription)"))
                        continuation.resume(returning: finalURL)
                    }
                }
            }
        }
    }

    private static func mixAudioTracksToSingleTrackIfNeeded(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try rewriteWithSingleAudioTrackIfNeeded(at: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func rewriteWithSingleAudioTrackIfNeeded(at url: URL) throws -> URL {
        let asset = AVURLAsset(url: url)
        let audioTracks = asset.tracks(withMediaType: .audio)

        guard audioTracks.count > 1 else {
            return url
        }

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw RecorderError.writerFailed("Could not find the video track for audio mixdown.")
        }

        let fileManager = FileManager.default
        let mixdownURL = temporarySiblingURL(for: url, suffix: "mixdown")
        try? fileManager.removeItem(at: mixdownURL)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: mixdownURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(videoOutput) else {
            throw RecorderError.writerFailed("Could not prepare video passthrough for audio mixdown.")
        }
        reader.add(videoOutput)

        let videoFormatHint = videoTrack.formatDescriptions.first.map { $0 as! CMFormatDescription }
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: videoFormatHint
        )
        videoInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerFailed("Could not prepare video writer for audio mixdown.")
        }
        writer.add(videoInput)

        let linearPCMSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: linearPCMSettings)
        audioOutput.alwaysCopiesSampleData = false
        audioOutput.audioMix = audioMix(for: audioTracks)

        guard reader.canAdd(audioOutput) else {
            throw RecorderError.writerFailed("Could not prepare audio reader for mixdown.")
        }
        reader.add(audioOutput)

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        audioInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(audioInput) else {
            throw RecorderError.writerFailed("Could not prepare mixed audio writer.")
        }
        writer.add(audioInput)

        guard reader.startReading() else {
            throw reader.error ?? RecorderError.writerFailed("Could not start reading tracks for audio mixdown.")
        }

        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? RecorderError.writerFailed("Could not start writing audio mixdown.")
        }

        writer.startSession(atSourceTime: .zero)

        try copySamples(
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioOutput: audioOutput,
            audioInput: audioInput,
            reader: reader,
            writer: writer
        )

        try replaceRecording(at: url, with: mixdownURL)
        return url
    }

    private static func audioMix(for audioTracks: [AVAssetTrack]) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        let volume = audioTracks.count > 1 ? Float(1.0 / sqrt(Double(audioTracks.count))) : 1.0
        mix.inputParameters = audioTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(volume, at: .zero)
            return parameters
        }
        return mix
    }

    private static func copySamples(
        videoOutput: AVAssetReaderTrackOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderAudioMixOutput,
        audioInput: AVAssetWriterInput,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) throws {
        let context = AudioMixdownCopyContext(
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioOutput: audioOutput,
            audioInput: audioInput,
            reader: reader,
            writer: writer
        )
        context.start()
        try context.waitForCompletion()
    }

    private static func replaceRecording(at originalURL: URL, with mixedURL: URL) throws {
        let fileManager = FileManager.default
        let backupURL = temporarySiblingURL(for: originalURL, suffix: "original")
        try? fileManager.removeItem(at: backupURL)

        try fileManager.moveItem(at: originalURL, to: backupURL)
        do {
            try fileManager.moveItem(at: mixedURL, to: originalURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            try? fileManager.moveItem(at: backupURL, to: originalURL)
            throw error
        }
    }

    private static func temporarySiblingURL(for url: URL, suffix: String) -> URL {
        let folder = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        return folder.appending(path: ".\(baseName)-\(suffix)-\(UUID().uuidString).mp4")
    }

    private func cleanupAfterStartFailure(writer: AVAssetWriter, error: Error) {
        stream = nil
        assetWriter = nil
        outputURL = nil
        audioTrackMode = .mixed
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
        sessionStarted = false
        finishing = false
        failed = false
        writer.cancelWriting()
        emit(.failed(error.recordyDescription))
    }

    private func failRecording(_ message: String) {
        guard !failed else {
            return
        }
        failed = true
        let streamToStop = stream
        stream = nil
        assetWriter?.cancelWriting()
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
        outputURL = nil
        audioTrackMode = .mixed
        sessionStarted = false
        finishing = false
        emit(.failed(message))

        if let streamToStop {
            Task {
                try? await streamToStop.stopCapture()
            }
        }
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

private final class AudioMixdownCopyContext: @unchecked Sendable {
    private let videoOutput: AVAssetReaderTrackOutput
    private let videoInput: AVAssetWriterInput
    private let audioOutput: AVAssetReaderAudioMixOutput
    private let audioInput: AVAssetWriterInput
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoQueue = DispatchQueue(label: "recordy.audio.mixdown.video")
    private let audioQueue = DispatchQueue(label: "recordy.audio.mixdown.audio")
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var copyError: Error?
    private var finishError: Error?
    private var videoFinished = false
    private var audioFinished = false

    init(
        videoOutput: AVAssetReaderTrackOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderAudioMixOutput,
        audioInput: AVAssetWriterInput,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) {
        self.videoOutput = videoOutput
        self.videoInput = videoInput
        self.audioOutput = audioOutput
        self.audioInput = audioInput
        self.reader = reader
        self.writer = writer
    }

    func start() {
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in
            copyVideo()
        }

        group.enter()
        audioInput.requestMediaDataWhenReady(on: audioQueue) { [self] in
            copyAudio()
        }
    }

    func waitForCompletion() throws {
        group.wait()

        if let error = currentCopyError() {
            throw error
        }

        if reader.status == .failed {
            throw reader.error ?? RecorderError.writerFailed("Audio mixdown reader failed.")
        }

        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { [self] in
            setFinishError(writer.error)
            finishSemaphore.signal()
        }
        finishSemaphore.wait()

        if let finishError = currentFinishError() {
            throw finishError
        }

        if writer.status != .completed {
            throw RecorderError.writerFailed("Audio mixdown did not complete.")
        }
    }

    private func copyVideo() {
        guard !videoFinished else {
            return
        }

        while videoInput.isReadyForMoreMediaData {
            if let error = currentCopyError() {
                finishVideo()
                setCopyError(error)
                return
            }

            guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                finishVideo()
                return
            }

            if !videoInput.append(sampleBuffer) {
                finishVideo()
                setCopyError(writer.error ?? RecorderError.writerFailed("Could not copy video during audio mixdown."))
                return
            }
        }
    }

    private func copyAudio() {
        guard !audioFinished else {
            return
        }

        while audioInput.isReadyForMoreMediaData {
            if let error = currentCopyError() {
                finishAudio()
                setCopyError(error)
                return
            }

            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                finishAudio()
                return
            }

            if !audioInput.append(sampleBuffer) {
                finishAudio()
                setCopyError(writer.error ?? RecorderError.writerFailed("Could not write mixed audio."))
                return
            }
        }
    }

    private func finishVideo() {
        guard !videoFinished else {
            return
        }
        videoInput.markAsFinished()
        videoFinished = true
        group.leave()
    }

    private func finishAudio() {
        guard !audioFinished else {
            return
        }
        audioInput.markAsFinished()
        audioFinished = true
        group.leave()
    }

    private func setCopyError(_ error: Error) {
        lock.lock()
        if copyError == nil {
            copyError = error
            reader.cancelReading()
            writer.cancelWriting()
        }
        lock.unlock()
    }

    private func currentCopyError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return copyError
    }

    private func setFinishError(_ error: Error?) {
        lock.lock()
        finishError = error
        lock.unlock()
    }

    private func currentFinishError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return finishError
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
              !failed,
              let writer = assetWriter else {
            return
        }

        if writer.status == .failed {
            failRecording(writer.error?.recordyDescription ?? "Recording failed.")
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            guard writer.startWriting() else {
                emit(.failed(writer.error?.recordyDescription ?? "Could not start writing."))
                return
            }
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        switch type {
        case .screen:
            guard isCompleteScreenFrame(sampleBuffer) else {
                return
            }
            guard let videoInput, videoInput.isReadyForMoreMediaData else {
                return
            }
            if !videoInput.append(sampleBuffer) {
                failRecording(writer.error?.recordyDescription ?? "Could not write video frame.")
            }
        case .audio:
            guard let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else {
                return
            }
            if !systemAudioInput.append(sampleBuffer) {
                failRecording(writer.error?.recordyDescription ?? "Could not write system audio frame.")
            }
        case .microphone:
            guard let microphoneInput, microphoneInput.isReadyForMoreMediaData else {
                return
            }
            if !microphoneInput.append(sampleBuffer) {
                failRecording(writer.error?.recordyDescription ?? "Could not write microphone frame.")
            }
        @unknown default:
            return
        }
    }

    private func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first,
            let rawStatus = attachments[.status],
            let status = SCFrameStatus(rawValue: statusRawValue(rawStatus)) else {
            return false
        }

        return status == .complete
    }

    private func statusRawValue(_ value: Any) -> Int {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return -1
    }
}

extension MacScreenCaptureRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failRecording(error.recordyDescription)
    }
}

private extension Error {
    var recordyDescription: String {
        let nsError = self as NSError
        let description = nsError.localizedDescription
        let failureReason = nsError.localizedFailureReason
        let recoverySuggestion = nsError.localizedRecoverySuggestion
        let domainAndCode = "\(nsError.domain) \(nsError.code)"

        return [description, failureReason, recoverySuggestion, domainAndCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}
