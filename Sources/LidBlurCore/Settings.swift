import Foundation

/// UserDefaults-backed preferences. Angles are not user-editable; only calibration is stored.
public final class Settings: @unchecked Sendable {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["enabled": true])
    }

    public var enabled: Bool {
        get { defaults.bool(forKey: "enabled") }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    public var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    /// User-chosen angle where the blur starts to appear while closing.
    public var startAngle: Double {
        get { defaults.object(forKey: "startAngle") as? Double ?? EngineConstants.defaultStartAngle }
        set {
            let r = EngineConstants.startAngleRange
            defaults.set(min(max(newValue, r.lowerBound), r.upperBound), forKey: "startAngle")
        }
    }

    public var calibratedDarkAngles: [Double] {
        get { defaults.array(forKey: "calibratedDarkAngles") as? [Double] ?? [] }
        set { defaults.set(Array(newValue.suffix(5)), forKey: "calibratedDarkAngles") }
    }

    /// Records the last angle seen before the display went dark. Implausible values are ignored.
    public func recordDarkAngle(_ angle: Double) {
        guard (5...60).contains(angle) else { return }
        calibratedDarkAngles += [angle]
    }

    public var fullAngle: Double {
        let a = calibratedDarkAngles.sorted()
        guard !a.isEmpty else { return EngineConstants.defaultFullAngle }
        let median = a.count % 2 == 1 ? a[a.count / 2] : (a[a.count / 2 - 1] + a[a.count / 2]) / 2
        return max(EngineConstants.defaultFullAngle, median + EngineConstants.calibrationMargin)
    }
}
