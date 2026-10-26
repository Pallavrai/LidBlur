import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()   // NSApplication.delegate is weak; this local lives as long as run()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
