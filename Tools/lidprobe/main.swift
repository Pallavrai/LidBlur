// lidprobe: one-day experiment tool for LidBlur (design file 1).
// Usage:
//   lidprobe sensor [--broad]   CSV of push reports + 120 Hz polled angle, plus screen sleep/wake marks
//   lidprobe overlay            built-in-display overlay driven by the angle; type a/b/c/m + Enter to switch
// Build: swiftc -O Tools/lidprobe/main.swift -o Tools/lidprobe/lidprobe

import AppKit
import IOKit.hid

let args = CommandLine.arguments.dropFirst()
let mode = args.first ?? "sensor"
let broad = args.contains("--broad")

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
func hex(_ b: UnsafeBufferPointer<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined() }

// MARK: Sensor

final class Sensor {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var device: IOHIDDevice?
    var pushBuffer = [UInt8](repeating: 0, count: 64)
    var onAngle: ((Double, String, String) -> Void)?

    func start() {
        var match: [String: Any] = [kIOHIDVendorIDKey: 0x05AC]
        if !broad {
            match[kIOHIDProductIDKey] = 0x8104
            match[kIOHIDDeviceUsagePageKey] = 0x20
            match[kIOHIDDeviceUsageKey] = 0x8A
        }
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let s = Unmanaged<Sensor>.fromOpaque(ctx!).takeUnretainedValue()
            let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? -1
            let page = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
            let usage = IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
            FileHandle.standardError.write("DEVICE_FOUND pid=0x\(String(pid, radix: 16)) page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16))\n".data(using: .utf8)!)
            guard pid == 0x8104, page == 0x20, usage == 0x8A else { return }
            s.device = dev
            s.pushBuffer.withUnsafeMutableBufferPointer { buf in
                IOHIDDeviceRegisterInputReportCallback(dev, buf.baseAddress!, buf.count, { ctx, _, _, _, _, report, len in
                    let s = Unmanaged<Sensor>.fromOpaque(ctx!).takeUnretainedValue()
                    let b = UnsafeBufferPointer(start: report, count: len)
                    if len >= 3 { s.onAngle?(Double(UInt16(b[2]) << 8 | UInt16(b[1])), "push", hex(b)) }
                }, ctx)
            }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            Unmanaged<Sensor>.fromOpaque(ctx!).takeUnretainedValue().device = nil
            FileHandle.standardError.write("DEVICE_REMOVED\n".data(using: .utf8)!)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        FileHandle.standardError.write("MANAGER_OPEN result=0x\(String(UInt32(bitPattern: r), radix: 16))\n".data(using: .utf8)!)
    }

    func poll() {
        guard let dev = device else { return }
        var buf = [UInt8](repeating: 0, count: 8)
        var len = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1, &buf, &len)
        guard r == kIOReturnSuccess, len >= 3 else { return }
        buf.withUnsafeBufferPointer { b in
            onAngle?(Double(UInt16(b[2]) << 8 | UInt16(b[1])), "poll", hex(UnsafeBufferPointer(rebasing: b[0..<len])))
        }
    }
}

// MARK: Overlay

final class Overlay {
    enum Variant: String { case a, b, c }   // a: blur only, b: blur + faster dim, c: dim only
    var variant = Variant.b
    let materials: [NSVisualEffectView.Material] = [.fullScreenUI, .hudWindow, .underWindowBackground]
    var materialIndex = 0
    var window: NSWindow?
    let effect = NSVisualEffectView()
    let dim = CALayer()
    let label = NSTextField(labelWithString: "")

    var builtIn: NSScreen? {
        NSScreen.screens.first { s in
            (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }
    }

    func teardown() { window?.orderOut(nil); window = nil }

    func apply(angle: Double) {
        guard let screen = builtIn,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              CGDisplayIsInMirrorSet(id) == 0 else { teardown(); return }
        let level = min(max((60 - angle) / (60 - 20), 0), 1)
        if window == nil { build(on: screen) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effect.alphaValue = variant == .c ? 0 : level
        dim.opacity = variant == .a ? 0 : Float(0.7 * pow(level, 0.6))
        CATransaction.commit()
        label.stringValue = String(format: "%.0f°  level %.2f  %@  %@", angle, level, variant.rawValue, "\(materials[materialIndex].rawValue)")
        if level > 0.001 { window?.orderFrontRegardless() } else { window?.orderOut(nil) }
    }

    func build(on screen: NSScreen) {
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true; w.level = .screenSaver; w.sharingType = .none
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.appearance = NSAppearance(named: .darkAqua)
        w.setFrame(screen.frame, display: false)
        let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        root.wantsLayer = true
        effect.frame = root.bounds; effect.autoresizingMask = [.width, .height]
        effect.blendingMode = .behindWindow; effect.state = .active; effect.material = materials[materialIndex]
        root.addSubview(effect)
        dim.frame = root.bounds; dim.backgroundColor = NSColor.black.cgColor
        root.layer?.addSublayer(dim)
        label.frame = NSRect(x: 20, y: 20, width: 600, height: 40)
        label.font = .monospacedSystemFont(ofSize: 28, weight: .bold); label.textColor = .systemRed
        root.addSubview(label)
        w.contentView = root
        window = w
    }

    func handle(_ cmd: String) {
        switch cmd {
        case "a", "b", "c": variant = Variant(rawValue: cmd)!
        case "m": materialIndex = (materialIndex + 1) % materials.count; effect.material = materials[materialIndex]
        default: break
        }
    }
}

// MARK: Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let sensor = Sensor()
var lastAngle: Double?
let overlay = Overlay()

if mode == "overlay" {
    sensor.onAngle = { a, _, _ in lastAngle = a; overlay.apply(angle: a) }
    CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
        if flags.contains(.beginConfigurationFlag) { DispatchQueue.main.async { overlay.teardown() } }
    }, nil)
    Thread.detachNewThread {
        while let line = readLine() {
            let cmd = line.trimmingCharacters(in: .whitespaces)
            DispatchQueue.main.async { overlay.handle(cmd); if let a = lastAngle { overlay.apply(angle: a) } }
        }
    }
} else {
    print("mono_time_ms,source,raw_hex,angle_deg")
    sensor.onAngle = { a, src, raw in lastAngle = a; print(String(format: "%.1f,%@,%@,%.0f", now(), src, raw, a)); fflush(stdout) }
}

let ws = NSWorkspace.shared.notificationCenter
for (name, tag) in [(NSWorkspace.screensDidSleepNotification, "SCREENS_DID_SLEEP"),
                    (NSWorkspace.screensDidWakeNotification, "SCREENS_DID_WAKE")] {
    ws.addObserver(forName: name, object: nil, queue: .main) { _ in
        print(String(format: "%@ %.1f last_angle=%@", tag, now(), lastAngle.map { "\($0)" } ?? "nil")); fflush(stdout)
    }
}

sensor.start()
Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in sensor.poll() }
app.run()
