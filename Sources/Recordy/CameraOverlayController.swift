import AppKit
@preconcurrency import AVFoundation

@MainActor
final class CameraOverlayController: NSObject {
    private weak var anchorWindow: NSWindow?
    private var panel: CameraPanel?
    private var previewView: CameraPreviewView?
    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "recordy.camera.session")
    private var generation = 0
    private var selectedCamera: CameraSource = .off
    private var shape: CameraShape = .circle
    private var size: CameraSize = .medium

    init(anchorWindow: NSWindow?) {
        self.anchorWindow = anchorWindow
        super.init()
    }

    func apply(camera: CameraSource) {
        selectedCamera = camera
        generation += 1
        let generation = generation

        guard let deviceID = camera.deviceID else {
            stop(generation: generation)
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start(deviceID: deviceID, generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    guard granted, self.generation == generation else {
                        self.stop(generation: generation)
                        return
                    }
                    self.start(deviceID: deviceID, generation: generation)
                }
            }
        default:
            stop(generation: generation)
        }
    }

    func setShape(_ shape: CameraShape) {
        self.shape = shape
        previewView?.setShape(shape)
        panel?.shape = shape
    }

    func setSize(_ size: CameraSize) {
        self.size = size
        guard let panel else {
            return
        }
        let side = max(panel.minSize.width, size.side)
        panel.setFrame(centeredFrame(panel.frame, side: side), display: true)
    }

    private func centeredFrame(_ frame: NSRect, side: CGFloat) -> NSRect {
        NSRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
    }

    private func start(deviceID: String, generation: Int) {
        guard selectedCamera.deviceID == deviceID, self.generation == generation else {
            return
        }

        stopSessionOnly()

        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device) else {
            stop(generation: generation)
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else {
            stop(generation: generation)
            return
        }
        session.addInput(input)

        let previewView = ensurePanel()
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill
        previewView.setShape(shape)

        captureSession = session
        let sessionQueue = sessionQueue
        sessionQueue.async {
            session.startRunning()
        }

        panel?.orderFrontRegardless()
    }

    private func stop(generation: Int) {
        guard self.generation == generation else {
            return
        }
        stopSessionOnly()
        panel?.orderOut(nil)
    }

    private func stopSessionOnly() {
        let session = captureSession
        captureSession = nil
        previewView?.previewLayer.session = nil
        if let session {
            sessionQueue.async {
                session.stopRunning()
            }
        }
    }

    private func ensurePanel() -> CameraPreviewView {
        if let panel, let previewView {
            panel.orderFrontRegardless()
            return previewView
        }

        let side = size.side
        let savedRelativeFrame = AppPreferences.loadCameraRelativeFrame()
        let savedFrame = savedRelativeFrame.flatMap { relativeFrame -> NSRect? in
            guard let anchorWindow else {
                return nil
            }
            return absoluteFrame(from: relativeFrame, anchorFrame: anchorWindow.frame)
        } ?? AppPreferences.loadCameraFrame()
        let base = savedFrame ?? NSRect(origin: defaultOrigin(size: side), size: NSSize(width: side, height: side))
        let panel = CameraPanel(
            contentRect: centeredFrame(base, side: side),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Recordy Webcam"
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.minSize = NSSize(width: 96, height: 96)
        panel.shape = shape
        panel.frameDidChange = { [weak self] frame in
            self?.cameraPanelFrameDidChange(frame)
        }

        let previewView = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        previewView.autoresizingMask = [.width, .height]
        previewView.setShape(shape)
        panel.contentView = previewView

        self.panel = panel
        self.previewView = previewView

        // Attach the overlay as a child of the capture window so the window server
        // moves it in lockstep with the anchor — smooth, zero-lag following with no
        // delta tracking. The child keeps its own offset, which updates when the user
        // drags the camera itself.
        if let anchorWindow {
            anchorWindow.addChildWindow(panel, ordered: .above)
        } else {
            panel.orderFrontRegardless()
        }
        return previewView
    }

    private func cameraPanelFrameDidChange(_ frame: NSRect) {
        AppPreferences.saveCameraFrame(frame)
        if let anchorWindow {
            AppPreferences.saveCameraRelativeFrame(relativeFrame(for: frame, anchorFrame: anchorWindow.frame))
        }
    }

    private func relativeFrame(for cameraFrame: NSRect, anchorFrame: NSRect) -> NSRect {
        NSRect(
            x: cameraFrame.minX - anchorFrame.minX,
            y: cameraFrame.minY - anchorFrame.minY,
            width: cameraFrame.width,
            height: cameraFrame.height
        )
    }

    private func absoluteFrame(from relativeFrame: NSRect, anchorFrame: NSRect) -> NSRect {
        NSRect(
            x: anchorFrame.minX + relativeFrame.minX,
            y: anchorFrame.minY + relativeFrame.minY,
            width: relativeFrame.width,
            height: relativeFrame.height
        )
    }

    private func defaultOrigin(size: CGFloat) -> CGPoint {
        if let anchorWindow {
            let frame = anchorWindow.frame
            return CGPoint(
                x: frame.maxX - size - 24,
                y: frame.minY + CaptureLayout.borderWidth + 24
            )
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return CGPoint(
            x: screenFrame.maxX - size - 32,
            y: screenFrame.minY + 32
        )
    }
}

final class CameraPanel: NSPanel, NSWindowDelegate {
    var shape: CameraShape = .circle
    var frameDidChange: ((NSRect) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let side = max(frameSize.width, frameSize.height)
        return NSSize(width: side, height: side)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        frameDidChange?(frame)
    }
}

final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private var shape: CameraShape = .circle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(previewLayer)
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .inVisibleRect],
                owner: self
            )
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    // Deliver the first click to a non-key window instead of swallowing it to
    // activate — lets a single click-drag move the overlay without a prior select click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        updateMask()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    func setShape(_ shape: CameraShape) {
        self.shape = shape
        updateMask()
    }

    private func updateMask() {
        previewLayer.masksToBounds = true
        previewLayer.cornerRadius = shape == .circle ? min(bounds.width, bounds.height) / 2 : 10
        previewLayer.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        previewLayer.borderWidth = 2
    }
}
