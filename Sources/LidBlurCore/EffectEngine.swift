import Foundation

/// Every tunable number lives here.
public enum EngineConstants {
    /// Starts early enough to be seen while the screen still faces the user, and below a typical open angle.
    public static let defaultStartAngle = 95.0
    /// Below ~70° the screen is hard to see from a normal seat, so a later start would show no visible effect.
    public static let startAngleRange = 70.0...110.0
    /// The full-effect angle is kept at least this far below the start angle.
    public static let minBandWidth = 10.0
    public static let defaultFullAngle = 20.0
    public static let calibrationMargin = 5.0
    public static let inputTimeout = 1.5
    public static let downMoveDegrees = 0.5
    /// Longer than the idle poll interval (0.1 s) so a sudden tilt is seen between two idle samples.
    public static let downMoveWindow = 0.15
    public static let emaTimeConstant = 0.015
    public static let staleTimeout = 0.5
    /// While the lid moves, the level eases toward the angle-driven target with this time constant,
    /// so it stays in step with the hinge and coarse or late samples never make it jump.
    public static let followTimeConstant = 0.03
    /// A dismissed blur fades out on an ease-out curve with this time constant (~1 s from full to invisible).
    public static let fadeTimeConstant = 0.15
    /// Last-resort safety net: a near-full blur with no input for this long is dismissed, in case input
    /// detection or the sensor is wrong. Long, because holding the lid still is meant to keep the blur.
    public static let watchdogLevel = 0.9
    public static let watchdogDuration = 120.0
    public static let bandMargin = 5.0
    public static let visibleThreshold = 0.001
}

public enum SensorStatus: String, Sendable { case searching, found, notFound, silent, invalid }

/// Raw values are the menu's status text.
public enum AppState: String, Sendable {
    case disabled = "Disabled", unsupported = "Unsupported", idle = "Idle", active = "Active", suspended = "Suspended"
}

/// Why the effect is off. Raw values are the menu's status text.
public enum Reason: String, Sendable {
    case none = ""
    case noSensor = "no lid-angle sensor"
    case sensorNotResponding = "sensor not responding"
    case noBuiltInDisplay = "built-in display off"
    case mirrored = "display mirrored"
    case reconfiguring = "displays changing"
    case asleep = "asleep"
    case sessionInactive = "session inactive"
    case waitingForSensor = "waiting for sensor"
    case dismissed = "dismissed until the lid closes further"
}

public struct AngleSample: Equatable, Sendable {
    public var angle: Double
    public var time: TimeInterval   // monotonic seconds
    public init(angle: Double, time: TimeInterval) { self.angle = angle; self.time = time }
}

public struct SystemState: Equatable, Sendable {
    public var systemAwake = true
    public var displayAwake = true
    public var sessionActive = true
    public var builtInDisplayID: UInt32? = 1
    public var builtInMirrored = false
    public var reconfiguring = false
    public var reduceTransparency = false
    public var reduceMotion = false
    /// Monotonic time of the last wake; samples taken at or before it are treated as stale.
    public var lastWakeTime: TimeInterval?
    public init() {}
}

public struct EngineInput: Sendable {
    public var now: TimeInterval
    public var enabled = true
    public var sensorStatus = SensorStatus.found
    public var sample: AngleSample?
    public var system = SystemState()
    public var secondsSinceInput = 1e9
    public var startAngle = EngineConstants.defaultStartAngle
    public var fullAngle = EngineConstants.defaultFullAngle
    public var previewLevel: Double?
    public init(now: TimeInterval) { self.now = now }
}

public struct EngineMemory: Sendable {
    var filteredAngle: Double?
    var lastSampleTime: TimeInterval?
    var history: [(time: TimeInterval, angle: Double)] = []
    /// Set by keyboard/pointer input (or the watchdog); cleared when the lid closes further.
    var dismissed = false
    var lastStepTime: TimeInterval?
    var level = 0.0
    var highLevelSince: TimeInterval?
    public init() {}
}

public struct EngineOutput: Equatable, Sendable {
    public var level = 0.0
    public var windowVisible = false
    public var appState = AppState.idle
    public var reason = Reason.none
    /// True when the scheduler should tick every display frame instead of the idle rate.
    public var inBand = false

    public init(level: Double = 0, windowVisible: Bool = false, appState: AppState = .idle,
                reason: Reason = .none, inBand: Bool = false) {
        (self.level, self.windowVisible, self.appState, self.reason, self.inBand) = (level, windowVisible, appState, reason, inBand)
    }
}

/// Pure decision function: one step of lid angle and system state in, effect level out. No AppKit, no timers.
public enum EffectEngine {
    public static func step(_ memory: EngineMemory, _ input: EngineInput) -> (EngineMemory, EngineOutput) {
        typealias K = EngineConstants
        let sys = input.system

        func gated(_ state: AppState, _ reason: Reason) -> (EngineMemory, EngineOutput) {
            var m = EngineMemory(); m.lastStepTime = input.now
            return (m, EngineOutput(appState: state, reason: reason))
        }
        // Keeps whatever is on screen without advancing the effect.
        func held(_ reason: Reason) -> (EngineMemory, EngineOutput) {
            var m = memory; m.lastStepTime = input.now; m.highLevelSince = nil
            return (m, EngineOutput(level: m.level, windowVisible: m.level > 0, appState: .suspended, reason: reason, inBand: true))
        }

        // Display and power gates apply to everything, preview included.
        if sys.builtInDisplayID == nil { return gated(.suspended, .noBuiltInDisplay) }
        if sys.builtInMirrored { return gated(.suspended, .mirrored) }
        if sys.reconfiguring { return gated(.suspended, .reconfiguring) }
        // Hold the blur through sleep, so a lid closed past the band wakes up blurred and clears as it opens.
        if !sys.systemAwake || !sys.displayAwake { return held(.asleep) }
        if !sys.sessionActive { return gated(.suspended, .sessionInactive) }

        if let p = input.previewLevel {
            var m = EngineMemory(); m.lastStepTime = input.now
            m.level = min(max(p, 0), 1)
            return (m, EngineOutput(level: m.level, windowVisible: m.level > K.visibleThreshold, appState: .active, inBand: true))
        }

        if !input.enabled { return gated(.disabled, .none) }
        switch input.sensorStatus {
        case .notFound: return gated(.unsupported, .noSensor)
        case .silent, .invalid: return gated(.unsupported, .sensorNotResponding)
        case .searching, .found: break
        }
        if let wake = sys.lastWakeTime, (input.sample?.time ?? -.infinity) <= wake {
            // Just woke: keep the held blur until a fresh reading arrives, and clear if none comes in time.
            return input.now - wake <= K.staleTimeout ? held(.waitingForSensor) : gated(.suspended, .waitingForSensor)
        }
        guard let sample = input.sample, input.now - sample.time <= K.staleTimeout else { return gated(.suspended, .waitingForSensor) }
        guard (0...360).contains(sample.angle) else { return gated(.unsupported, .sensorNotResponding) }

        var m = memory
        let dt = m.lastStepTime.map { max(input.now - $0, 0) } ?? 0
        m.lastStepTime = input.now

        // Filter: short EMA, skipped under Reduce Motion so the effect tracks the raw lid angle.
        if sample.time != m.lastSampleTime {
            if let f = m.filteredAngle, let last = m.lastSampleTime, !sys.reduceMotion {
                m.filteredAngle = f + (1 - exp(-(sample.time - last) / K.emaTimeConstant)) * (sample.angle - f)
            } else {
                m.filteredAngle = sample.angle
            }
            m.lastSampleTime = sample.time
            m.history.append((sample.time, m.filteredAngle!))
        }
        m.history.removeAll { sample.time - $0.time > K.downMoveWindow }
        let f = m.filteredAngle!
        let movingDown = f - (m.history.first?.angle ?? f) <= -K.downMoveDegrees

        let fullAngle = min(input.fullAngle, input.startAngle - K.minBandWidth)
        let t = min(max((input.startAngle - f) / (input.startAngle - fullAngle), 0), 1)
        let raw = t * t * (3 - 2 * t)

        // Input dismisses the blur until the lid closes further; holding the lid still keeps it.
        if input.secondsSinceInput < K.inputTimeout { m.dismissed = true } else if movingDown { m.dismissed = false }

        // Holding or opening: the blur stays or recedes with the lid, never grows without closing motion,
        // so a low angle seen right after wake can't bring the blur back by itself.
        let target = m.dismissed ? 0 : (movingDown ? raw : min(m.level, raw))

        // Exponential approach in both directions: an ease-out that tracks the hinge, never a jump or a hard stop.
        let tau = m.dismissed ? K.fadeTimeConstant : K.followTimeConstant
        m.level += (target - m.level) * (dt > 0 ? 1 - exp(-dt / tau) : 0)
        if m.level < K.visibleThreshold { m.level = 0 }   // end the exponential tail

        if m.level > K.watchdogLevel {
            m.highLevelSince = m.highLevelSince ?? input.now
            if input.now - m.highLevelSince! > K.watchdogDuration { m.dismissed = true; m.highLevelSince = nil }
        } else {
            m.highLevelSince = nil
        }

        let visible = m.level > 0
        return (m, EngineOutput(level: m.level, windowVisible: visible, appState: visible ? .active : .idle,
                                reason: m.dismissed ? .dismissed : .none,
                                inBand: f < input.startAngle + K.bandMargin || visible || movingDown))
    }
}
