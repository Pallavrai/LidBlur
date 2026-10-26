import Foundation
import IOKit.hid
import LidBlurCore

/// The only file that touches IOKit HID. Polled by the scheduler (the sensor only pushes a ~1 Hz heartbeat).
@MainActor
final class HIDLidSensor {
    private(set) var status = SensorStatus.searching { didSet { if status != oldValue { onStatus?(status) } } }
    private(set) var latest: AngleSample?
    private(set) var lastRawBytes: [UInt8] = []
    var onStatus: ((SensorStatus) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private var invalidStreak = 0
    private var startedAt = 0.0

    func start() {
        // Exact four-key match: broad Apple-vendor matching would also open the keyboard and may prompt for Input Monitoring.
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104,
                                    kIOHIDDeviceUsagePageKey: 0x20, kIOHIDDeviceUsageKey: 0x8A]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            MainActor.assumeIsolated {
                let s = Unmanaged<HIDLidSensor>.fromOpaque(ctx!).takeUnretainedValue()
                // Re-arm detection so a sensor that re-registers after wake (or appears late) resumes polling.
                s.device = dev; s.status = .searching; s.startedAt = ProcessInfo.processInfo.systemUptime
            }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            MainActor.assumeIsolated {
                let s = Unmanaged<HIDLidSensor>.fromOpaque(ctx!).takeUnretainedValue()
                s.device = nil; s.latest = nil; s.status = .searching; s.startedAt = ProcessInfo.processInfo.systemUptime
            }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        startedAt = ProcessInfo.processInfo.systemUptime
    }

    func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let dev = device else {
            if status == .searching, now - startedAt > 2 { status = .notFound }
            return
        }
        var buf = [UInt8](repeating: 0, count: 8)
        var len = CFIndex(buf.count)
        guard IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1, &buf, &len) == kIOReturnSuccess, len >= 3 else {
            if latest.map({ now - $0.time > 2 }) ?? (now - startedAt > 2) { status = .silent }
            return
        }
        lastRawBytes = Array(buf[0..<len])
        let angle = Double(UInt16(buf[2]) << 8 | UInt16(buf[1]))
        if let prev = latest, now > prev.time, abs(angle - prev.angle) / (now - prev.time) > 2000 || !(0...360).contains(angle) {
            invalidStreak += 1
            if invalidStreak >= 10 { status = .invalid }
            return
        }
        invalidStreak = 0
        latest = AngleSample(angle: angle, time: now)
        status = .found
    }

    func stop() { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)); device = nil; latest = nil }
}
