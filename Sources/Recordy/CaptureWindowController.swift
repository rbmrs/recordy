import AppKit
import SwiftUI

@MainActor
final class CaptureWindowController: NSWindowController {
    private let viewModel: RecorderViewModel
    private var passThroughTimer: Timer?
    private var lastWindowOrigin: CGPoint?
    var originDidChange: ((CGPoint) -> Void)?

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel

        let panel = CapturePanel(
            contentRect: AppPreferences.loadCaptureFrame() ?? NSRect(x: 240, y: 240, width: 960, height: 600),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Recordy"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.minSize = CaptureLayout.minimumWindowSize
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.captureAspectRatio = viewModel.settings.aspectRatio
        panel.delegate = panel

        super.init(window: panel)

        lastWindowOrigin = panel.frame.origin
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        let hostingView = CaptureHostingView(rootView: RecorderView(viewModel: viewModel), viewModel: viewModel)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        viewModel.regionProvider = { [weak panel] in
            Self.captureRegion(for: panel, scale: viewModel.settings.quality.outputScale)
        }

        startPassThroughTracking(for: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setAspectRatio(_ aspectRatio: CaptureAspectRatio) {
        (window as? CapturePanel)?.updateAspectRatio(aspectRatio)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if AppPreferences.loadCaptureFrame() == nil {
            window?.center()
        }
        lastWindowOrigin = window?.frame.origin
        window?.makeKeyAndOrderFront(sender)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        let newOrigin = window.frame.origin
        guard let lastWindowOrigin else {
            self.lastWindowOrigin = newOrigin
            return
        }

        let delta = CGPoint(
            x: newOrigin.x - lastWindowOrigin.x,
            y: newOrigin.y - lastWindowOrigin.y
        )
        self.lastWindowOrigin = newOrigin

        if delta.x != 0 || delta.y != 0 {
            originDidChange?(delta)
        }
    }

    private func startPassThroughTracking(for panel: NSPanel) {
        passThroughTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self, weak panel] _ in
            guard let self, let panel else {
                return
            }
            Task { @MainActor in
                self.updateMousePassThrough(for: panel)
            }
        }
    }

    private func updateMousePassThrough(for panel: NSPanel) {
        let shouldPassThrough = shouldPassMouseEventsThroughWindow(panel)
        if panel.ignoresMouseEvents != shouldPassThrough {
            panel.ignoresMouseEvents = shouldPassThrough
        }
    }

    private func shouldPassMouseEventsThroughWindow(_ panel: NSPanel) -> Bool {
        guard !viewModel.settingsDropdownOpen else {
            return false
        }

        let mouseLocation = NSEvent.mouseLocation
        let frame = panel.frame

        guard frame.contains(mouseLocation) else {
            return false
        }

        let localPoint = NSPoint(
            x: mouseLocation.x - frame.minX,
            y: mouseLocation.y - frame.minY
        )

        return Self.isInteriorPassThroughPoint(localPoint, in: frame.size)
    }

    private static func captureRegion(for window: NSWindow?, scale: Double) -> CaptureRegion? {
        guard let window else {
            return nil
        }

        let frame = window.frame
        let captureFrame = NSRect(
            x: frame.minX + CaptureLayout.borderWidth,
            y: frame.minY + CaptureLayout.borderWidth,
            width: frame.width - (CaptureLayout.borderWidth * 2),
            height: frame.height - CaptureLayout.toolbarHeight - CaptureLayout.borderWidth
        )

        guard captureFrame.width >= 32, captureFrame.height >= 32 else {
            return nil
        }

        let screenIntersections: [(screen: NSScreen, intersection: NSRect)] = NSScreen.screens.compactMap { screen in
            let intersection = screen.frame.intersection(captureFrame)
            guard !intersection.isNull, !intersection.isEmpty else {
                return nil
            }
            return (screen, intersection)
        }

        guard let screen = screenIntersections.max(by: { left, right in
            left.intersection.width * left.intersection.height < right.intersection.width * right.intersection.height
        })?.screen else {
            return nil
        }

        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        let localRect = displayLocalRect(appKitRect: captureFrame, screenFrame: screen.frame)
        let backingScale = screen.backingScaleFactor
        let outputWidth = evenDimension(localRect.width * backingScale * scale)
        let outputHeight = evenDimension(localRect.height * backingScale * scale)

        return CaptureRegion(
            screenRect: localRect,
            displayID: displayID,
            outputSize: CGSize(width: outputWidth, height: outputHeight),
            excludedWindowIDs: [CGWindowID(window.windowNumber)]
        )
    }

    private static func displayLocalRect(appKitRect: NSRect, screenFrame: NSRect) -> CGRect {
        CGRect(
            x: appKitRect.minX - screenFrame.minX,
            y: screenFrame.maxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        max(2, Int(value.rounded(.down)) / 2 * 2)
    }

    fileprivate static func isInteriorPassThroughPoint(_ point: NSPoint, in size: CGSize) -> Bool {
        let topBarMinY = size.height - CaptureLayout.toolbarHeight
        let edge = CaptureLayout.resizeHitWidth
        let isResizeEdge = point.x <= edge
            || point.x >= size.width - edge
            || point.y <= edge
            || point.y >= size.height - edge

        return point.y < topBarMinY && !isResizeEdge
    }
}

final class CapturePanel: NSPanel, NSWindowDelegate {
    var captureAspectRatio: CaptureAspectRatio = .free

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func updateAspectRatio(_ aspectRatio: CaptureAspectRatio) {
        captureAspectRatio = aspectRatio
        applyAspectRatioToCurrentFrame()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        constrainedSize(for: frameSize)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        AppPreferences.saveCaptureFrame(frame)
    }

    private func applyAspectRatioToCurrentFrame() {
        guard captureAspectRatio.ratio != nil else {
            return
        }

        let adjustedSize = constrainedSize(for: frame.size)
        guard adjustedSize != frame.size else {
            return
        }

        let currentTop = frame.maxY
        var adjustedFrame = frame
        adjustedFrame.size = adjustedSize
        adjustedFrame.origin.y = currentTop - adjustedSize.height
        setFrame(adjustedFrame, display: true)
    }

    private func constrainedSize(for proposedSize: NSSize) -> NSSize {
        guard let ratio = captureAspectRatio.ratio else {
            return proposedSize
        }

        let borderWidth = CaptureLayout.borderWidth
        let captureWidthInset = borderWidth * 2
        let captureHeightInset = CaptureLayout.toolbarHeight + borderWidth
        let minimumCaptureWidth = max(32, minSize.width - captureWidthInset)
        let minimumCaptureHeight = max(32, minSize.height - captureHeightInset)

        let proposedCaptureWidth = proposedSize.width - captureWidthInset
        let proposedCaptureHeight = proposedSize.height - captureHeightInset

        // Project the proposed box onto the aspect-ratio line (nearest point on
        // width = ratio * height). This depends ONLY on the proposed size, so the
        // same proposal always yields the same result. The old code chose the locked
        // axis by comparing against the current frame — which was the size this
        // method had just produced — so the choice flipped every event and the
        // window oscillated between two sizes (the resize flicker).
        var captureHeight = (ratio * proposedCaptureWidth + proposedCaptureHeight) / (ratio * ratio + 1)
        var captureWidth = captureHeight * ratio

        if captureWidth < minimumCaptureWidth {
            captureWidth = minimumCaptureWidth
            captureHeight = captureWidth / ratio
        }

        if captureHeight < minimumCaptureHeight {
            captureHeight = minimumCaptureHeight
            captureWidth = captureHeight * ratio
        }

        return NSSize(
            width: captureWidth + captureWidthInset,
            height: captureHeight + captureHeightInset
        )
    }
}

final class CaptureHostingView: NSHostingView<RecorderView> {
    private weak var viewModel: RecorderViewModel?

    init(rootView: RecorderView, viewModel: RecorderViewModel) {
        self.viewModel = viewModel
        super.init(rootView: rootView)
    }

    required init(rootView: RecorderView) {
        self.viewModel = rootView.viewModel
        super.init(rootView: rootView)
    }

    @MainActor
    @preconcurrency required dynamic init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        if viewModel?.settingsDropdownOpen == true {
            return super.hitTest(point)
        }

        if isInteriorPassThroughPoint(point) {
            return nil
        }

        return super.hitTest(point)
    }

    private func isInteriorPassThroughPoint(_ point: NSPoint) -> Bool {
        CaptureWindowController.isInteriorPassThroughPoint(point, in: bounds.size)
    }
}
