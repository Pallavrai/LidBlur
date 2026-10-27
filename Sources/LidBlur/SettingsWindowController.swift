import AppKit
import SwiftUI

/// Owns the Settings window. Shown on first launch, from the menu, and whenever the app is opened again,
/// which is how users reach it when the menu-bar icon is hidden.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let releasesURL = URL(string: "https://github.com/Pallavrai/LidBlur/releases")!

    private unowned let app: AppDelegate
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    init(app: AppDelegate) { self.app = app }

    func show() {
        app.syncSettingsModel(full: true)
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(app: app, model: app.settingsModel)))
            w.title = "LidBlur Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()   // no Dock icon, so bring the window forward explicitly
        window?.makeKeyAndOrderFront(nil)
        app.refreshScheduler()
    }

    func windowWillClose(_ notification: Notification) { app.settings.hasLaunchedBefore = true }
}
