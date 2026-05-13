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

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()

        let recorder = MacScreenCaptureRecorder()
        let viewModel = RecorderViewModel(engine: recorder)
        let controller = CaptureWindowController(viewModel: viewModel)
        captureWindowController = controller

        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
