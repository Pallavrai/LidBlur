import Foundation

/// Every tunable number lives here. Values are provisional until the lidprobe experiment answers Q1–Q4.
public enum EngineConstants {
    /// At 60° the screen is already hard to see from a normal seat, so the effect starts earlier.
    public static let defaultStartAngle = 80.0
    public static let startAngleRange = 30.0...110.0
    /// The full-effect angle is kept at least this far below the start angle.
    public static let minBandWidth = 10.0
    public static let defaultFullAngle = 20.0
    public static let calibrationMargin = 5.0
    public static let holdAngle = 25.0
    public static let stillTimeout = 2.0
    public static let inputTimeout = 1.5
    public static let downMoveDegrees = 0.5
    /// Longer than the idle poll interval (0.1 s) so a sudden tilt is seen between two idle samples.
    public static let downMoveWindow = 0.15
    public static let emaTimeConstant = 0.015
    public static let staleTimeout = 0.5
    /// Shortest time a full effect takes to fade out; slow enough to read as a fade, not a snap.
    public static let clearDuration = 0.6
    /// The level eases toward the lid-driven target with this time constant, so late or coarse samples never make it jump.
    public static let riseTimeConstant = 0.03
    public static let watchdogLevel = 0.9
    public static let watchdogDuration = 10.0
    public static let bandMargin = 5.0
    public static let visibleThreshold = 0.001
}

public enum SensorStatus: String, Sendable { case searching, found, notFound, silent, invalid }

public enum AppState: String, Sendable { case disabled, unsupported, idle, active, suspended }

public enum Reason: String, Sendable {
    case userDisabled, panic, watchdog, noSensor, sensorSilent, sensorInvalid
    case noBuiltInDisplay, mirrored, reconfiguring, asleep, sessionInactive, justWoke
    case stale, still, recentInput, opening, none
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
    public var disabledReason: Reason?
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
    var lastDownMoveTime: TimeInterval?
    var lastStepTime: TimeInterval?
    public internal(set) var level = 0.0
    var highLevelSince: TimeInterval?
    public init() {}
}

public struct EngineOutput: Equatable, Sendable {
    public var level = 0.0
    public var windowVisible = false
    public var appState = AppState.idle
    public var reason = Reason.none
    public var filteredAngle: Double?
    public var requestDisable: Reason?
    /// True when the scheduler should tick every display frame instead of the idle rate.
    public var inBand = false

    public init(level: Double = 0, windowVisible: Bool = false, appState: AppState = .idle, reason: Reason = .none,
                filteredAngle: Double? = nil, requestDisable: Reason? = nil, inBand: Bool = false) {
        self.level = level; self.windowVisible = windowVisible; self.appState = appState; self.reason = reason
        self.filteredAngle = filteredAngle; self.requestDisable = requestDisable; self.inBand = inBand
    }
}

public enum EffectEngine {
    public static func step(_ memory: EngineMemory, _ input: EngineInput) -> (EngineMemory, EngineOutput) {
        typealias K = EngineConstants
        let sys = input.system

        func gated(_ state: AppState, _ reason: Reason) -> (EngineMemory, EngineOutput) {
            var m = EngineMemory(); m.lastStepTime = input.now
            return (m, EngineOutput(appState: state, reason: reason))
        }

        // Display and power gates apply to everything, preview included.
        if sys.builtInDisplayID == nil { return gated(.suspended, .noBuiltInDisplay) }
        if sys.builtInMirrored { return gated(.suspended, .mirrored) }
        if sys.reconfiguring { return gated(.suspended, .reconfiguring) }
        if !sys.systemAwake || !sys.displayAwake { return gated(.suspended, .asleep) }
        if !sys.sessionActive { return gated(.suspended, .sessionInactive) }

        if let p = input.previewLevel {
            var m = EngineMemory(); m.lastStepTime = input.now
            let level = min(max(p, 0), 1)
            m.level = level
            return (m, EngineOutput(level: level, windowVisible: level > K.visibleThreshold,
                                    appState: .active, reason: .none, inBand: true))
        }

        if !input.enabled { return gated(.disabled, input.disabledReason ?? .userDisabled) }
        switch input.sensorStatus {
        case .notFound: return gated(.unsupported, .noSensor)
        case .silent: return gated(.unsupported, .sensorSilent)
        case .invalid: return gated(.unsupported, .sensorInvalid)
        case .searching, .found: break
        }
        guard let sample = input.sample, input.now - sample.time <= K.staleTimeout else { return gated(.suspended, .stale) }
        if let wake = sys.lastWakeTime, sample.time <= wake { return gated(.suspended, .justWoke) }
        guard (0...360).contains(sample.angle) else { return gated(.unsupported, .sensorInvalid) }

        var m = memory
        let dt = m.lastStepTime.map { max(input.now - $0, 0) } ?? 0
        m.lastStepTime = input.now

        // Filter: short EMA, skipped under Reduce Motion so the effect tracks the raw lid angle.
        if sample.time != m.lastSampleTime {
            if let f = m.filteredAngle, let last = m.lastSampleTime, !sys.reduceMotion {
                let a = 1 - exp(-(sample.time - last) / K.emaTimeConstant)
                m.filteredAngle = f + a * (sample.angle - f)
            } else {
                m.filteredAngle = sample.angle
            }
            m.lastSampleTime = sample.time
            m.history.append((sample.time, m.filteredAngle!))
        }
        m.history.removeAll { sample.time - $0.time > K.downMoveWindow }
        let f = m.filteredAngle!
        let delta = f - (m.history.first?.angle ?? f)
        let movingDown = delta <= -K.downMoveDegrees
        let movingUp = delta >= K.downMoveDegrees
        if movingDown { m.lastDownMoveTime = input.now }

        let fullAngle = min(input.fullAngle, input.startAngle - K.minBandWidth)
        let t = min(max((input.startAngle - f) / (input.startAngle - fullAngle), 0), 1)
        let raw = t * t * (3 - 2 * t)

        var target: Double
        var reason = Reason.none
        if input.secondsSinceInput < K.inputTimeout {
            target = 0; reason = .recentInput
        } else if movingUp {
            target = 0; reason = .opening
        } else if f > K.holdAngle, m.lastDownMoveTime.map({ input.now - $0 > K.stillTimeout }) ?? true {
            target = 0; reason = .still
        } else if movingDown || f <= K.holdAngle {
            target = raw
        } else {
            target = min(m.level, raw)   // brief pause above holdAngle: may fall, may not rise
        }

        // Rise eases toward the hand's position (a short exponential catch-up); fall is a linear fade.
        if target >= m.level {
            m.level += (target - m.level) * (dt > 0 ? 1 - exp(-dt / K.riseTimeConstant) : 0)
        } else {
            m.level = max(target, m.level - dt / K.clearDuration)
        }

        var out = EngineOutput()
        if m.level > K.watchdogLevel {
            m.highLevelSince = m.highLevelSince ?? input.now
            if input.now - m.highLevelSince! > K.watchdogDuration {
                var cleared = EngineMemory(); cleared.lastStepTime = input.now
                return (cleared, EngineOutput(appState: .disabled, reason: .watchdog, filteredAngle: f, requestDisable: .watchdog))
            }
        } else {
            m.highLevelSince = nil
        }

        out.level = m.level
        out.windowVisible = m.level > K.visibleThreshold
        out.appState = out.windowVisible ? .active : .idle
        out.reason = reason
        out.filteredAngle = f
        out.inBand = f < input.startAngle + K.bandMargin || m.level > 0 || movingDown
        return (m, out)
    }
}
