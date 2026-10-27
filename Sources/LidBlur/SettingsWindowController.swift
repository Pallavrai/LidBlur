import AppKit
import LidBlurCore
import ServiceManagement

/// The app's settings window. Shown on first launch, from the menu, and whenever the app is opened again,
/// which is how users reach it when the menu-bar icon is hidden.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let releasesURL = URL(string: "https://github.com/Pallavrai/LidBlur/releases")!

    private unowned let app: AppDelegate
    private var window: NSWindow?
    private let header = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let startLabel = NSTextField(labelWithString: "")
    private lazy var enabled = NSButton(checkboxWithTitle: "Enable LidBlur", target: self, action: #selector(toggleEnabled))
    private lazy var login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin))
    private lazy var menuIcon = NSButton(checkboxWithTitle: "Show icon in menu bar", target: self, action: #selector(toggleMenuIcon))
    private lazy var startSlider = NSSlider(value: EngineConstants.defaultStartAngle,
                                            minValue: EngineConstants.startAngleRange.lowerBound,
                                            maxValue: EngineConstants.startAngleRange.upperBound,
                                            target: self, action: #selector(sliderMoved))
    private lazy var useCurrent = NSButton(title: "Use Current Lid Angle", target: self, action: #selector(useCurrentAngle))
    private lazy var preview = NSButton(title: "Preview Effect", target: self, action: #selector(previewPressed))

    var isVisible: Bool { window?.isVisible == true }

    init(app: AppDelegate) { self.app = app }

    func show() {
        if window == nil { window = makeWindow() }
        refresh()
        NSApp.activate()   // no Dock icon, so bring the window forward explicitly
        window?.makeKeyAndOrderFront(nil)
        app.refreshScheduler()
    }

    /// Called every tick while visible. Only the live status changes, so controls aren't reset mid-drag.
    func refreshStatusIfVisible() {
        if isVisible { status.stringValue = app.statusText }
    }

    private func refresh() {
        let supported = app.sensor.status != .notFound
        header.stringValue = supported
            ? "LidBlur blurs and dims your MacBook's screen as you close the lid, and clears it as you open it or use "
              + "the keyboard or trackpad. It only affects the built-in display and is not a privacy tool.\n\n"
              + "If the screen ever stays blurred, press Control-Option-Command-B to quit LidBlur."
            : "This Mac has no lid-angle sensor LidBlur can read, so the effect can't run here."
        status.stringValue = app.statusText
        enabled.state = app.settings.enabled ? .on : .off
        let loginStatus = SMAppService.mainApp.status
        login.state = loginStatus == .enabled ? .on : .off
        login.title = loginStatus == .requiresApproval ? "Launch at login (approve in System Settings)" : "Launch at login"
        menuIcon.state = app.settings.showMenuBarIcon ? .on : .off
        startSlider.doubleValue = app.settings.startAngle
        startLabel.stringValue = "Blur starts at \(Int(app.settings.startAngle.rounded()))°"
        for control in [enabled, login, startSlider, useCurrent, preview] as [NSControl] { control.isEnabled = supported }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "LidBlur Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self

        header.preferredMaxLayoutWidth = 420
        status.textColor = .secondaryLabelColor
        let iconHint = NSTextField(wrappingLabelWithString: "When the icon is hidden, open LidBlur again from Applications to return here.")
        iconHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        iconHint.textColor = .secondaryLabelColor
        iconHint.preferredMaxLayoutWidth = 400
        startSlider.widthAnchor.constraint(equalToConstant: 260).isActive = true

        func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
        let rule = { () -> NSBox in let b = NSBox(); b.boxType = .separator; return b }
        let rules = [rule(), rule(), rule()]
        let stack = NSStackView(views: [
            header, status, rules[0],
            enabled, login, menuIcon, iconHint, rules[1],
            startLabel, NSStackView(views: [startSlider, useCurrent]), rules[2],
            NSStackView(views: [preview, button("Copy Diagnostics", #selector(copyDiagnostics)),
                                button("Check for Updates…", #selector(releases)), button("Quit", #selector(quit))]),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: menuIcon)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for r in rules { r.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
        w.contentView = stack
        w.center()
        return w
    }

    func windowWillClose(_ notification: Notification) { app.settings.hasLaunchedBefore = true }

    @objc private func toggleEnabled() { app.setEnabled(enabled.state == .on) }
    @objc private func toggleMenuIcon() { app.setShowMenuBarIcon(menuIcon.state == .on) }
    @objc private func toggleLogin() {
        do {
            if login.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
    @objc private func sliderMoved() {
        app.setStartAngle(startSlider.doubleValue.rounded())
        startLabel.stringValue = "Blur starts at \(Int(app.settings.startAngle.rounded()))°"
    }
    @objc private func useCurrentAngle() {
        if let angle = app.sensor.latest?.angle { app.setStartAngle(angle) }
        refresh()
    }
    @objc private func previewPressed() { app.startPreview() }
    @objc private func copyDiagnostics() { app.copyDiagnostics() }
    @objc private func releases() { NSWorkspace.shared.open(Self.releasesURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
