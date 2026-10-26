import AppKit
import LidBlurCore
import os

@MainActor
enum Diagnostics {
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lidblur", category: "engine")

    static func logTick(_ out: EngineOutput, sample: AngleSample?, system: SystemState) {
        guard out.inBand else { return }
        log.debug("""
            t=\(sample?.time ?? 0, format: .fixed(precision: 3)) raw=\(sample?.angle ?? -1) \
            filt=\(out.filteredAngle ?? -1, format: .fixed(precision: 1)) level=\(out.level, format: .fixed(precision: 3)) \
            state=\(out.appState.rawValue) reason=\(out.reason.rawValue) display=\(system.builtInDisplayID ?? 0) mirrored=\(system.builtInMirrored)
            """)
    }

    static func report(sensor: HIDLidSensor, settings: Settings, system: SystemState, last: EngineOutput, hotKeyError: OSStatus) -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        let info = Bundle.main.infoDictionary ?? [:]
        return """
            LidBlur \(info["CFBundleShortVersionString"] ?? "dev") (\(info["CFBundleVersion"] ?? "-"))
            Model: \(model)
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Sensor: \(sensor.status.rawValue), last angle \(sensor.latest.map { "\(Int($0.angle))°" } ?? "none"), raw \(sensor.lastRawBytes.map { String(format: "%02x", $0) }.joined())
            Thresholds: start \(settings.startAngle)°, full \(settings.fullAngle)°, calibration \(settings.calibratedDarkAngles)
            Enabled: \(settings.enabled), disabled reason: \(settings.disabledReason?.rawValue ?? "none")
            State: \(last.appState.rawValue), reason \(last.reason.rawValue), level \(last.level)
            Displays: \(NSScreen.screens.map { "\(SystemMonitor.displayID($0))\(CGDisplayIsBuiltin(SystemMonitor.displayID($0)) != 0 ? " (built-in)" : "")" }.joined(separator: ", ")), built-in mirrored: \(system.builtInMirrored)
            Panic hotkey: \(hotKeyError == noErr ? "registered" : "failed (\(hotKeyError))")
            """
    }
}
