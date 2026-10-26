import AppKit

/// Idle: a slow timer. In the band: one tick per display frame. Stopped while asleep, disabled or unsupported.
@MainActor
final class TickScheduler {
    enum Mode { case stopped, idle, band }
    private(set) var mode = Mode.stopped
    private var timer: Timer?
    private var link: CADisplayLink?
    private var activity: NSObjectProtocol?
    private let tick: @MainActor () -> Void
    /// Fast enough to catch the start of a close; the engine's motion window is sized to it.
    static let idleInterval = 0.1

    init(tick: @escaping @MainActor () -> Void) { self.tick = tick }

    func setMode(_ new: Mode, screen: NSScreen?) {
        guard new != mode else { return }
        timer?.invalidate(); timer = nil
        link?.invalidate(); link = nil
        mode = new
        switch new {
        case .stopped:
            if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
            return
        case .idle:
            let t = Timer(timeInterval: Self.idleInterval, repeats: true) { _ in MainActor.assumeIsolated { self.tick() } }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            timer = t
        case .band:
            guard let screen else { return setMode(.idle, screen: nil) }
            let l = screen.displayLink(target: self, selector: #selector(frame))
            l.add(to: .main, forMode: .common)
            link = l
        }
        // Keeps App Nap from stretching idle ticks; still allows idle system sleep.
        activity = activity ?? ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "lid angle")
    }

    /// Display links are tied to one screen; drop it after any display change.
    func invalidateDisplayLink() { if mode == .band { link?.invalidate(); link = nil; mode = .stopped } }

    @objc private func frame() { tick() }
}
