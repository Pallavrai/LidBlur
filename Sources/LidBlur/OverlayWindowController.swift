import AppKit

/// The only owner of the overlay window. Shown only while the level is above zero; destroyed on display changes.
@MainActor
final class OverlayWindowController {
    static let material = NSVisualEffectView.Material.fullScreenUI
    static let maxDim: Float = 0.7

    private var window: NSWindow?
    private var effect: NSVisualEffectView?
    private var dim: CALayer?
    private var builtFor: CGDirectDisplayID?

    func apply(level: Double, visible: Bool, reduceTransparency: Bool, on screen: NSScreen?) {
        guard visible, let screen else { return hide() }
        prepare(on: screen)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effect?.alphaValue = reduceTransparency ? 0 : level
        dim?.opacity = Self.maxDim * Float(pow(level, 0.6))   // dim rises faster than blur to hide the crossfade ghost
        CATransaction.commit()
        window?.orderFrontRegardless()
    }

    /// Builds the window ahead of the first visible frame, so showing it never stalls a frame.
    /// Keyed by display ID: an ordered-out window reports no screen, which used to force a rebuild on every show.
    func prepare(on screen: NSScreen) {
        if window == nil || builtFor != SystemMonitor.displayID(screen) { build(on: screen) }
    }

    func hide() { window?.orderOut(nil) }

    func teardown() {
        window?.orderOut(nil)
        window = nil; effect = nil; dim = nil; builtFor = nil
    }

    private func build(on screen: NSScreen) {
        teardown()
        let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.sharingType = .none
        w.isExcludedFromWindowsMenu = true
        w.isReleasedWhenClosed = false
        w.setAccessibilityElement(false)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.appearance = NSAppearance(named: .darkAqua)
        w.setFrame(screen.frame, display: false)

        let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        root.wantsLayer = true
        let e = NSVisualEffectView(frame: root.bounds)
        e.autoresizingMask = [.width, .height]
        e.material = Self.material
        e.blendingMode = .behindWindow
        e.state = .active   // an app without a Dock icon is never "active", so force the live look
        root.addSubview(e)
        let d = CALayer()
        d.frame = root.bounds
        d.backgroundColor = NSColor.black.cgColor
        d.opacity = 0
        root.layer?.addSublayer(d)
        w.contentView = root
        window = w; effect = e; dim = d; builtFor = SystemMonitor.displayID(screen)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
