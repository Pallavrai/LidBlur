import AppKit
import LidBlurCore

/// Watches sleep/wake, session, displays and accessibility settings, and publishes one SystemState.
@MainActor
final class SystemMonitor {
    private(set) var state = SystemState()
    var onChange: ((SystemState) -> Void)?
    /// Called with the moment the screens go dark, so calibration can record the last angle.
    var onScreensDidSleep: (() -> Void)?

    func start() {
        let ws = NSWorkspace.shared
        let nc = ws.notificationCenter   // sleep/wake/a11y notifications are posted here, not on NotificationCenter.default
        func on(_ name: Notification.Name, _ change: @escaping @MainActor (inout SystemState) -> Void) {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(change) }
            }
        }
        let woke: @MainActor (inout SystemState) -> Void = { $0.lastWakeTime = ProcessInfo.processInfo.systemUptime }
        on(NSWorkspace.willSleepNotification) { $0.systemAwake = false }
        on(NSWorkspace.didWakeNotification) { $0.systemAwake = true; woke(&$0) }
        on(NSWorkspace.screensDidSleepNotification) { [weak self] in $0.displayAwake = false; self?.onScreensDidSleep?() }
        on(NSWorkspace.screensDidWakeNotification) { $0.displayAwake = true; woke(&$0) }
        on(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        on(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        on(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { _ in }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update { $0.reconfiguring = false } }
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, ctx in
            let begin = flags.contains(.beginConfigurationFlag)
            // Runs on the main thread; hide synchronously on "begin" so macOS never moves the overlay to another screen.
            MainActor.assumeIsolated {
                Unmanaged<SystemMonitor>.fromOpaque(ctx!).takeUnretainedValue().update { $0.reconfiguring = begin }
            }
        }, ctx)
        update { _ in }
    }

    private func update(_ change: (inout SystemState) -> Void) {
        var s = state
        change(&s)
        let builtIn = Self.builtInScreen
        s.builtInDisplayID = builtIn.map(Self.displayID)
        s.builtInMirrored = s.builtInDisplayID.map { CGDisplayIsInMirrorSet($0) != 0 } ?? false
        s.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        s.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if s != state { state = s; onChange?(s) }
    }

    static var builtInScreen: NSScreen? { NSScreen.screens.first { CGDisplayIsBuiltin(displayID($0)) != 0 } }
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Seconds since the last key, pointer or scroll event. Reads timing only, never event contents.
    static func secondsSinceInput() -> Double {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .scrollWheel, .leftMouseDown]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 1e9
    }
}
