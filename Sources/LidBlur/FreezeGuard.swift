import Foundation
import os

/// Background safety net: if the main thread stops ticking while the overlay is on screen, quit the process.
/// The window server removes a dead app's windows, so the screen clears even when the hotkey can't run.
final class FreezeGuard: @unchecked Sendable {
    static let timeout = 2.0
    private let state = OSAllocatedUnfairLock(initialState: (beat: 0.0, overlayVisible: false))
    private let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))

    func start() {
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [state] in
            let (beat, visible) = state.withLock { $0 }
            if visible, ProcessInfo.processInfo.systemUptime - beat > Self.timeout {
                Logger(subsystem: "com.pallavrai.lidblur", category: "engine").fault("Main thread stalled with overlay visible; exiting")
                exit(0)
            }
        }
        timer.resume()
    }

    /// Called from every main-thread tick.
    func beat(overlayVisible: Bool) {
        state.withLock { $0 = (ProcessInfo.processInfo.systemUptime, overlayVisible) }
    }
}
