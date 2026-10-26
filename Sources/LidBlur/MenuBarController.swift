import AppKit
import LidBlurCore
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let releasesURL = URL(string: "https://github.com/Pallavrai/LidBlur/releases")!

    private unowned let app: AppDelegate
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let startLabel = NSTextField(labelWithString: "")
    private let startSlider = NSSlider()
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
        func entry(_ title: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; return i
        }
        enabledItem.target = self
        loginItem.target = self
        menu.items = [
            statusLine, .separator(), enabledItem, loginItem, .separator(),
            sliderItem(),
            entry("Start Blur at Current Lid Angle", #selector(useCurrentAngle)),
            .separator(),
            entry("Preview Effect", #selector(preview)),
            entry("Copy Diagnostics", #selector(copyDiagnostics)),
            entry("About LidBlur", #selector(about)),
            entry("Check for Updates…", #selector(releases)),
            .separator(),
            NSMenuItem(title: "Quit LidBlur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        item.menu = menu
    }

    private func sliderItem() -> NSMenuItem {
        startSlider.minValue = EngineConstants.startAngleRange.lowerBound
        startSlider.maxValue = EngineConstants.startAngleRange.upperBound
        startSlider.isContinuous = true
        startSlider.target = self
        startSlider.action = #selector(sliderMoved)
        startSlider.widthAnchor.constraint(equalToConstant: 232).isActive = true
        startLabel.font = .menuFont(ofSize: 0)
        let stack = NSStackView(views: [startLabel, startSlider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 50)
        let item = NSMenuItem()
        item.view = stack
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { isOpen = true; app.refreshScheduler() }
    func menuDidClose(_ menu: NSMenu) { isOpen = false; app.refreshScheduler() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshIfOpen(force: true)
        enabledItem.state = app.settings.enabled ? .on : .off
        enabledItem.isEnabled = app.last.appState != .unsupported
        updateStartControls()
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        loginItem.title = status == .requiresApproval ? "Launch at Login (approve in System Settings)" : "Launch at Login"
    }

    /// Called every tick so the live lid angle updates while the menu is open.
    func refreshIfOpen(force: Bool = false) {
        guard isOpen || force else { return }
        let angle = app.sensor.latest.map { "Lid \(Int($0.angle))°" } ?? ""
        statusLine.title = [app.last.appState.rawValue, app.last.reason.rawValue, angle]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func updateStartControls() {
        startSlider.doubleValue = app.settings.startAngle
        startLabel.stringValue = "Blur starts at \(Int(app.settings.startAngle.rounded()))°"
    }

    /// Shows an alert on failure; returns whether the change took effect.
    @discardableResult
    static func setLaunchAtLogin(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    @objc private func toggleEnabled() { app.setEnabled(!app.settings.enabled) }
    @objc private func toggleLogin() { Self.setLaunchAtLogin(SMAppService.mainApp.status != .enabled) }
    @objc private func sliderMoved() { app.setStartAngle(startSlider.doubleValue.rounded()); updateStartControls() }
    @objc private func useCurrentAngle() { if let a = app.sensor.latest?.angle { app.setStartAngle(a) } }
    @objc private func preview() { app.startPreview() }
    @objc private func copyDiagnostics() { app.copyDiagnostics() }
    @objc private func about() { app.showWelcome() }
    @objc private func releases() { NSWorkspace.shared.open(Self.releasesURL) }
}
