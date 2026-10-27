import AppKit
import LidBlurCore

/// Wires the parts together. Every tick: poll sensor → build input → EffectEngine.step → overlay, scheduler, menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    let sensor = HIDLidSensor()
    private(set) var last = EngineOutput()
    private let monitor = SystemMonitor()
    private let overlay = OverlayWindowController()
    private let hotKey = PanicHotKey()
    private let freezeGuard = FreezeGuard()
    private lazy var menu = MenuBarController(app: self)
    private lazy var settingsWindow = SettingsWindowController(app: self)
    private lazy var scheduler = TickScheduler { [unowned self] in tick() }
    private var memory = EngineMemory()
    private var previewStart: Double?
    private static let previewDuration = 1.5

    func applicationDidFinishLaunching(_ notification: Notification) {
        sensor.onStatus = { [unowned self] _ in refreshScheduler() }
        monitor.onChange = { [unowned self] state in
            if state.reconfiguring {
                overlay.teardown()
                scheduler.invalidateDisplayLink()
            }
            tick()
        }
        monitor.onScreensDidSleep = { [unowned self] in
            if let s = sensor.latest { settings.recordDarkAngle(s.angle) }
        }
        sensor.start()
        monitor.start()
        hotKey.register()
        freezeGuard.start()
        _ = menu
        if !settings.hasLaunchedBefore {
            // Wait out the sensor's 2 s detection window so the window's text matches this Mac.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [unowned self] in showSettings() }
        }
        refreshScheduler()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() { settingsWindow.show() }

    func setShowMenuBarIcon(_ show: Bool) {
        settings.showMenuBarIcon = show
        menu.setVisible(show)
    }

    var statusText: String {
        [last.appState.rawValue, last.reason.rawValue, sensor.latest.map { "Lid \(Int($0.angle))°" } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func setEnabled(_ on: Bool) {
        settings.enabled = on
        tick()
    }

    func setStartAngle(_ angle: Double) {
        settings.startAngle = angle
        tick()
    }

    func startPreview() {
        previewStart = ProcessInfo.processInfo.systemUptime
        refreshScheduler()
    }

    func refreshScheduler() {
        let s = monitor.state
        let runnable = s.systemAwake && s.displayAwake && s.sessionActive && s.builtInDisplayID != nil
            && (settings.enabled || previewStart != nil) && sensor.status != .notFound
        // Open UI keeps the sensor polled so the live angle readout works even while disabled.
        let uiOpen = (menu.isOpen || settingsWindow.isVisible) && sensor.status != .notFound && s.displayAwake
        let mode: TickScheduler.Mode = runnable ? (last.inBand || previewStart != nil ? .band : .idle) : (uiOpen ? .idle : .stopped)
        scheduler.setMode(mode, screen: SystemMonitor.builtInScreen)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if scheduler.mode != .stopped { sensor.poll() }

        var input = EngineInput(now: now)
        input.enabled = settings.enabled
        input.sensorStatus = sensor.status
        input.sample = sensor.latest
        input.system = monitor.state
        input.startAngle = settings.startAngle
        input.fullAngle = settings.fullAngle
        // Input timing only matters near the band; skipping it keeps idle ticks cheap.
        if let a = input.sample?.angle, a < input.startAngle + EngineConstants.bandMargin {
            input.secondsSinceInput = SystemMonitor.secondsSinceInput()
        }
        if let start = previewStart {
            let p = (now - start) / Self.previewDuration
            if p >= 1 { previewStart = nil } else { input.previewLevel = sin(.pi * p) }
        }

        (memory, last) = EffectEngine.step(memory, input)

        let screen = SystemMonitor.builtInScreen
        if last.inBand, let screen { overlay.prepare(on: screen) }
        overlay.apply(level: last.level, visible: last.windowVisible, reduceTransparency: input.system.reduceTransparency, on: screen)
        // While asleep there are no ticks by design, so the freeze guard must not count a held blur.
        freezeGuard.beat(overlayVisible: last.windowVisible && last.reason != .asleep)
        menu.refreshIfOpen()
        settingsWindow.refreshStatusIfVisible()
        refreshScheduler()
    }

    func copyDiagnostics() {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let info = Bundle.main.infoDictionary ?? [:]
        let displays = NSScreen.screens.map {
            let id = SystemMonitor.displayID($0)
            return "\(id)\(CGDisplayIsBuiltin(id) != 0 ? " (built-in)" : "")"
        }
        let report = """
            LidBlur \(info["CFBundleShortVersionString"] ?? "dev") (\(info["CFBundleVersion"] ?? "-"))
            Model: \(String(decoding: model.prefix { $0 != 0 }, as: UTF8.self))
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Sensor: \(sensor.status.rawValue), angle \(sensor.latest.map { "\(Int($0.angle))°" } ?? "none"), raw \(sensor.lastRawBytes.map { String(format: "%02x", $0) }.joined())
            Angles: start \(settings.startAngle)°, full \(settings.fullAngle)°, calibration \(settings.calibratedDarkAngles)
            Enabled: \(settings.enabled), state: \(last.appState.rawValue) \(last.reason.rawValue), level \(last.level)
            Displays: \(displays.joined(separator: ", ")), built-in mirrored: \(monitor.state.builtInMirrored)
            Quit hotkey: \(hotKey.registrationError == noErr ? "registered" : "failed (\(hotKey.registrationError))")
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
