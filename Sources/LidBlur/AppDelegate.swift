import AppKit
import LidBlurCore

/// Wires the parts together. Every tick: poll sensor → build input → EffectEngine.step → overlay/scheduler/menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let sensor = HIDLidSensor()
    private let monitor = SystemMonitor()
    private let overlay = OverlayWindowController()
    private let welcome = WelcomeWindowController()
    private lazy var scheduler = TickScheduler { [unowned self] in tick() }
    private lazy var hotKey = PanicHotKey { [unowned self] in forceQuit() }
    private let freezeGuard = FreezeGuard()
    private var menu: MenuBarController?
    private var memory = EngineMemory()
    private var last = EngineOutput()
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

        menu = MenuBarController(actions: .init(
            status: { [unowned self] in (last, sensor.latest) },
            isEnabled: { [unowned self] in settings.enabled },
            startAngle: { [unowned self] in settings.startAngle },
            setStartAngle: { [unowned self] a in settings.startAngle = a; tick() },
            menuOpenChanged: { [unowned self] in refreshScheduler() },
            setEnabled: { [unowned self] on in setEnabled(on) },
            preview: { [unowned self] in startPreview() },
            copyDiagnostics: { [unowned self] in copyDiagnostics() },
            showWelcome: { [unowned self] in welcome.show() }))

        welcome.supported = { [unowned self] in sensor.status != .notFound }
        welcome.isEnabled = { [unowned self] in settings.enabled }
        welcome.onPreview = { [unowned self] in startPreview() }
        welcome.onEnable = { [unowned self] in setEnabled(true) }
        welcome.onClose = { [unowned self] in settings.hasLaunchedBefore = true }
        if !settings.hasLaunchedBefore {
            // Give the sensor its 2 s detection window so the window shows the right message.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [unowned self] in welcome.show() }
        }
        refreshScheduler()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        welcome.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.teardown()
        sensor.stop()
        hotKey.unregister()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if scheduler.mode != .stopped { sensor.poll() }

        var input = EngineInput(now: now)
        input.enabled = settings.enabled
        input.disabledReason = settings.disabledReason
        input.sensorStatus = sensor.status
        input.sample = sensor.latest
        input.system = monitor.state
        // Input timing only matters near the band; skipping it keeps idle ticks cheap.
        if let a = input.sample?.angle, a < settings.startAngle + EngineConstants.bandMargin {
            input.secondsSinceInput = SystemMonitor.secondsSinceInput()
        }
        input.startAngle = settings.startAngle
        input.fullAngle = settings.fullAngle
        if let start = previewStart {
            let p = (now - start) / Self.previewDuration
            if p >= 1 { previewStart = nil } else { input.previewLevel = sin(.pi * p) }
        }

        let (m, out) = EffectEngine.step(memory, input)
        memory = m
        last = out

        if out.inBand, !out.windowVisible, let screen = SystemMonitor.builtInScreen { overlay.prepare(on: screen) }
        overlay.apply(level: out.level, visible: out.windowVisible,
                      reduceTransparency: input.system.reduceTransparency, on: SystemMonitor.builtInScreen)
        freezeGuard.beat(overlayVisible: out.windowVisible)
        menu?.refreshIfOpen()
        Diagnostics.logTick(out, sample: input.sample, system: input.system)
        refreshScheduler()
    }

    private func refreshScheduler() {
        let s = monitor.state
        let runnable = s.systemAwake && s.displayAwake && s.sessionActive && s.builtInDisplayID != nil
            && (settings.enabled || previewStart != nil) && sensor.status != .notFound
        // An open menu keeps the sensor polled so its live angle readout works even while disabled.
        let menuOpen = menu?.isOpen == true && sensor.status != .notFound && s.displayAwake
        let mode: TickScheduler.Mode = runnable ? (last.inBand || previewStart != nil ? .band : .idle) : (menuOpen ? .idle : .stopped)
        scheduler.setMode(mode, screen: SystemMonitor.builtInScreen)
        if mode == .stopped, !last.windowVisible { overlay.hide() }
    }

    private func setEnabled(_ on: Bool) {
        settings.enabled = on
        settings.disabledReason = on ? nil : .userDisabled
        if !on { overlay.teardown() }
        tick()
        refreshScheduler()
    }

    /// Hotkey escape hatch: remove the overlay and quit immediately, restoring the normal screen.
    private func forceQuit() {
        overlay.teardown()
        hotKey.unregister()
        exit(0)
    }

    private func startPreview() {
        previewStart = ProcessInfo.processInfo.systemUptime
        refreshScheduler()
    }

    private func copyDiagnostics() {
        let text = Diagnostics.report(sensor: sensor, settings: settings, system: monitor.state,
                                      last: last, hotKeyError: hotKey.registrationError)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
