import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.regular)
withExtendedLifetime(delegate) {
    app.run()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var captureWindowController: CaptureWindowController?
    private var cameraOverlayController: CameraOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()

        let recorder = MacScreenCaptureRecorder()
        let viewModel = RecorderViewModel(engine: recorder)
        let controller = CaptureWindowController(viewModel: viewModel)
        let cameraOverlay = CameraOverlayController(anchorWindow: controller.window)
        viewModel.cameraSelectionChanged = { [weak cameraOverlay] camera in
            Task { @MainActor in
                cameraOverlay?.apply(camera: camera)
            }
        }
        viewModel.cameraShapeChanged = { [weak cameraOverlay] shape in
            Task { @MainActor in
                cameraOverlay?.setShape(shape)
            }
        }
        viewModel.aspectRatioChanged = { [weak controller] aspectRatio in
            Task { @MainActor in
                controller?.setAspectRatio(aspectRatio)
            }
        }
        viewModel.syncCameraOverlay()
        viewModel.syncCaptureWindowSettings()
        captureWindowController = controller
        cameraOverlayController = cameraOverlay

        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HomebrewUpdater.shared.runAutomaticUpdateOnQuit()
    }

    private func installMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            NSMenuItem(
                title: "Quit Recordy",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }
}
