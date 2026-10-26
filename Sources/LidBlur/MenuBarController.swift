import AppKit
import LidBlurCore
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Actions {
        var status: () -> (EngineOutput, AngleSample?)
        var isEnabled: () -> Bool
        var startAngle: () -> Double
        var setStartAngle: (Double) -> Void
        var menuOpenChanged: () -> Void
        var setEnabled: (Bool) -> Void
        var preview: () -> Void
        var copyDiagnostics: () -> Void
        var showWelcome: () -> Void
    }

    /// shortcut: assumes the GitHub repo will live here; change when the repository is created.
    static let releasesURL = URL(string: "https://github.com/pallavrai/LidBlur/releases")!

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let actions: Actions
    private let startLabel = NSTextField(labelWithString: "")
    private let startSlider = NSSlider()
    private(set) var isOpen = false

    init(actions: Actions) {
        self.actions = actions
        super.init()
        let image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "LidBlur")
        image?.isTemplate = true
        item.button?.image = image
        statusLine.isEnabled = false
        menu.autoenablesItems = false
        menu.delegate = self
        for i in [enabledItem, loginItem] { i.target = self }
        menu.items = [
            statusLine, .separator(), enabledItem, loginItem, .separator(),
            sliderItem(),
            target(NSMenuItem(title: "Start Blur at Current Lid Angle", action: #selector(useCurrentAngle), keyEquivalent: "")),
            .separator(),
            target(NSMenuItem(title: "Preview Effect", action: #selector(preview), keyEquivalent: "")),
            target(NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")),
            target(NSMenuItem(title: "About LidBlur…", action: #selector(about), keyEquivalent: "")),
            target(NSMenuItem(title: "Releases Page", action: #selector(releases), keyEquivalent: "")),
            .separator(),
            NSMenuItem(title: "Quit LidBlur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        item.menu = menu
    }

    private func target(_ i: NSMenuItem) -> NSMenuItem { i.target = self; return i }

    private func sliderItem() -> NSMenuItem {
        let r = EngineConstants.startAngleRange
        startSlider.minValue = r.lowerBound
        startSlider.maxValue = r.upperBound
        startSlider.isContinuous = true
        startSlider.target = self
        startSlider.action = #selector(sliderMoved)
        startLabel.font = .menuFont(ofSize: 0)
        let stack = NSStackView(views: [startLabel, startSlider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 50)
        startSlider.widthAnchor.constraint(equalToConstant: 232).isActive = true
        let item = NSMenuItem()
        item.view = stack
        return item
    }

    private func updateStartControls() {
        let a = actions.startAngle()
        startSlider.doubleValue = a
        startLabel.stringValue = "Blur starts at \(Int(a.rounded()))°"
    }

    func menuWillOpen(_ menu: NSMenu) { isOpen = true; actions.menuOpenChanged() }
    func menuDidClose(_ menu: NSMenu) { isOpen = false; actions.menuOpenChanged() }

    /// Called every tick so the live lid angle updates while the menu is open.
    func refreshIfOpen() {
        guard isOpen else { return }
        let (out, sample) = actions.status()
        statusLine.title = Self.statusText(out, angle: sample?.angle)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let (out, sample) = actions.status()
        statusLine.title = Self.statusText(out, angle: sample?.angle)
        enabledItem.state = actions.isEnabled() ? .on : .off
        updateStartControls()
        enabledItem.isEnabled = out.appState != .unsupported
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on; loginItem.title = "Launch at Login"
        case .requiresApproval: loginItem.state = .mixed; loginItem.title = "Launch at Login (needs approval in System Settings)"
        default: loginItem.state = .off; loginItem.title = "Launch at Login"
        }
    }

    static func statusText(_ out: EngineOutput, angle: Double?) -> String {
        let state: String = switch out.appState {
        case .disabled: "Disabled"
        case .unsupported: "Unsupported"
        case .idle: "Idle"
        case .active: "Active"
        case .suspended: "Suspended"
        }
        let reason: String? = switch out.reason {
        case .userDisabled: "turned off"
        case .panic: "panic hotkey pressed"
        case .watchdog: "stayed blurred too long"
        case .noSensor: "no lid-angle sensor"
        case .sensorSilent, .sensorInvalid: "sensor not responding"
        case .noBuiltInDisplay: "built-in display off"
        case .mirrored: "display mirrored"
        case .reconfiguring: "displays changing"
        case .asleep: "asleep"
        case .sessionInactive: "screen locked"
        case .justWoke, .stale: "waiting for sensor"
        case .still, .recentInput, .opening, .none: nil
        }
        return ([state, reason, angle.map { "Lid \(Int($0))°" }].compactMap { $0 }).joined(separator: " · ")
    }

    /// Returns an error message, or nil on success.
    static func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @objc private func toggleEnabled() { actions.setEnabled(!actions.isEnabled()) }
    @objc private func toggleLogin() {
        if let err = Self.setLaunchAtLogin(SMAppService.mainApp.status != .enabled) {
            NSAlert(error: NSError(domain: "LidBlur", code: 1, userInfo: [NSLocalizedDescriptionKey: err])).runModal()
        }
    }
    @objc private func sliderMoved() { actions.setStartAngle(startSlider.doubleValue.rounded()); updateStartControls() }
    @objc private func useCurrentAngle() {
        if let a = actions.status().1?.angle { actions.setStartAngle(a) }
    }
    @objc private func preview() { actions.preview() }
    @objc private func copyDiagnostics() { actions.copyDiagnostics() }
    @objc private func about() { actions.showWelcome() }
    @objc private func releases() { NSWorkspace.shared.open(Self.releasesURL) }
}
