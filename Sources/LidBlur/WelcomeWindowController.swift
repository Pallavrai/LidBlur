import AppKit
import ServiceManagement

/// First-launch and reopen window. Keeps the app reachable when the menu-bar icon is hidden behind the notch.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    var supported: () -> Bool = { true }
    var isEnabled: () -> Bool = { false }
    var onPreview: () -> Void = {}
    var onEnable: () -> Void = {}
    var onClose: () -> Void = {}
    private var window: NSWindow?

    func show() {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "LidBlur"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let body = supported()
            ? "LidBlur blurs and dims the MacBook screen as you close the lid, and clears it when the lid stops or opens. "
              + "It only affects the built-in display.\n\nThis is a visual effect, not a privacy tool.\n\n"
              + "If the screen ever stays blurred, press Control-Option-Command-B to quit LidBlur immediately.\n\n"
              + "You can change the angle where the blur starts from the menu-bar icon."
            : "This Mac has no lid-angle sensor LidBlur can read, so LidBlur can't do anything here.\n\nYou can quit it from the menu bar."
        let text = NSTextField(wrappingLabelWithString: body)
        text.preferredMaxLayoutWidth = 400

        let preview = NSButton(title: "Preview Effect", target: self, action: #selector(previewPressed))
        let enable = NSButton(title: "Enable", target: self, action: #selector(enablePressed))
        enable.isHidden = !supported() || isEnabled()
        let login = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(loginToggled(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = supported()

        let buttons = NSStackView(views: [preview, enable])
        let stack = NSStackView(views: [text, login, buttons])
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

    func windowWillClose(_ notification: Notification) { onClose() }

    @objc private func previewPressed() { onPreview() }
    @objc private func enablePressed(_ sender: NSButton) { onEnable(); sender.isHidden = true }
    @objc private func loginToggled(_ sender: NSButton) {
        if let err = MenuBarController.setLaunchAtLogin(sender.state == .on) {
            sender.state = sender.state == .on ? .off : .on
            NSAlert(error: NSError(domain: "LidBlur", code: 1, userInfo: [NSLocalizedDescriptionKey: err])).runModal()
        }
    }
}
