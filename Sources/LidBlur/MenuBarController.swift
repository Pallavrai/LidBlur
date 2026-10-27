import AppKit

/// Optional menu-bar icon with quick actions. Everything else lives in the Settings window.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private(set) var isOpen = false

    init(app: AppDelegate) {
        self.app = app
        super.init()
        let image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "LidBlur")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusLine.isEnabled = false
        enabledItem.target = self
        func entry(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.target = self; return i
        }
        menu.items = [
            statusLine, .separator(),
            enabledItem,
            entry("Start Blur at Current Lid Angle", #selector(useCurrentAngle)),
            entry("Preview Effect", #selector(preview)),
            .separator(),
            entry("Settings…", #selector(settings), ","),
            .separator(),
            NSMenuItem(title: "Quit LidBlur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        item.menu = menu
        setVisible(app.settings.showMenuBarIcon)
    }

    func setVisible(_ visible: Bool) { item.isVisible = visible }

    func menuWillOpen(_ menu: NSMenu) { isOpen = true; app.refreshScheduler() }
    func menuDidClose(_ menu: NSMenu) { isOpen = false; app.refreshScheduler() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusLine.title = app.statusText
        enabledItem.state = app.settings.enabled ? .on : .off
        enabledItem.isEnabled = app.sensor.status != .notFound
    }

    /// Called every tick so the live lid angle updates while the menu is open.
    func refreshIfOpen() {
        if isOpen { statusLine.title = app.statusText }
    }

    @objc private func toggleEnabled() { app.setEnabled(!app.settings.enabled) }
    @objc private func useCurrentAngle() { if let a = app.sensor.latest?.angle { app.setStartAngle(a) } }
    @objc private func preview() { app.startPreview() }
    @objc private func settings() { app.showSettings() }
}
