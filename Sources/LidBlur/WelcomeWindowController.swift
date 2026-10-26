import AppKit
import ServiceManagement

/// First-launch and reopen window. Keeps the app reachable when the menu-bar icon is hidden behind the notch.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var window: NSWindow?

    init(app: AppDelegate) { self.app = app }

    func show() {
        window?.close()
        let supported = app.sensor.status != .notFound
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "LidBlur"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let body = supported
            ? "LidBlur blurs and dims the MacBook screen as you close the lid, and clears it as you open the lid "
              + "or use the keyboard or trackpad. It only affects the built-in display.\n\n"
              + "This is a visual effect, not a privacy tool.\n\n"
              + "If the screen ever stays blurred, press Control-Option-Command-B to quit LidBlur immediately.\n\n"
              + "You can change the angle where the blur starts from the menu-bar icon."
            : "This Mac has no lid-angle sensor LidBlur can read, so LidBlur can't do anything here.\n\nYou can quit it from the menu bar."
        let text = NSTextField(wrappingLabelWithString: body)
        text.preferredMaxLayoutWidth = 400

        let preview = NSButton(title: "Preview Effect", target: self, action: #selector(previewPressed))
        let enable = NSButton(title: "Enable", target: self, action: #selector(enablePressed))
        enable.isHidden = !supported || app.settings.enabled
        let login = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(loginToggled))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = supported

        let stack = NSStackView(views: [text, login, NSStackView(views: [preview, enable])])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        w.contentView = stack
        w.center()
        window = w
        NSApp.activate()   // no Dock icon, so bring the window forward explicitly
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { app.settings.hasLaunchedBefore = true }

    @objc private func previewPressed() { app.startPreview() }
    @objc private func enablePressed(_ sender: NSButton) { app.setEnabled(true); sender.isHidden = true }
    @objc private func loginToggled(_ sender: NSButton) {
        if !MenuBarController.setLaunchAtLogin(sender.state == .on) { sender.state = sender.state == .on ? .off : .on }
    }
}
