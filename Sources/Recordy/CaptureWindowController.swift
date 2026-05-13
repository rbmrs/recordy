import AppKit
import SwiftUI

@MainActor
final class CaptureWindowController: NSWindowController {
    private let viewModel: RecorderViewModel
    private var passThroughTimer: Timer?

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel

        let panel = CapturePanel(
            contentRect: NSRect(x: 240, y: 240, width: 760, height: 460),
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
        panel.minSize = NSSize(width: 520, height: 320)
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        super.init(window: panel)

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

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
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
            outputSize: CGSize(width: outputWidth, height: outputHeight)
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

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
