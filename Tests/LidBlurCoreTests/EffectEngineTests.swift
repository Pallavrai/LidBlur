import XCTest
@testable import LidBlurCore

/// Replays a synthetic lid trace through the engine at 120 Hz.
/// Traces are generated in code (not JSON files): they are simple functions of time.
private struct Run {
    var outputs: [(t: Double, out: EngineOutput)] = []
    func at(_ t: Double) -> EngineOutput { outputs.last { $0.t <= t + 1e-9 }!.out }
    var maxLevel: Double { outputs.map(\.out.level).max() ?? 0 }
}

private func replay(duration: Double, angle: (Double) -> Double?,
                    configure: (Double, inout EngineInput) -> Void = { _, _ in }) -> Run {
    var memory = EngineMemory()
    var run = Run()
    var lastSample: AngleSample?
    let dt = 1.0 / 120
    var t = 0.0
    while t <= duration {
        if let a = angle(t) { lastSample = AngleSample(angle: a, time: t) }
        var input = EngineInput(now: t)
        input.sample = lastSample
        configure(t, &input)
        let (m, out) = EffectEngine.step(memory, input)
        memory = m
        run.outputs.append((t, out))
        t += dt
    }
    return run
}

/// Linear close from `from` to `to` over `seconds`, starting at `start`.
private func close(from: Double = 110, to: Double = 5, start: Double = 0.2, seconds: Double) -> (Double) -> Double {
    { t in
        if t < start { return from }
        let p = min((t - start) / seconds, 1)
        return from + (to - from) * p
    }
}

final class EffectEngineTests: XCTestCase {
    func testFastCloseReachesFullBeforeScreenGoesDark() {
        let trace = close(seconds: 0.4)   // ~260°/s
        let run = replay(duration: 0.8, angle: trace)
        // fullAngle is calibrated to (dark angle + margin), so the panel goes dark at fullAngle − margin.
        let darkAngle = EngineConstants.defaultFullAngle - EngineConstants.calibrationMargin
        let atDark = run.outputs.first { trace($0.t) <= darkAngle }!
        XCTAssertGreaterThanOrEqual(atDark.out.level, 0.95)
        XCTAssertTrue(atDark.out.windowVisible)
    }

    func testSuddenTiltEasesInWithoutJumping() {
        // Models the app's scheduler: 10 Hz samples while idle, one per 1/120 s frame once the engine reports inBand.
        // A sudden tilt (110° → 30° in 0.15 s) must be noticed early and the level must ease in, not jump.
        let trace = close(to: 30, start: 0.25, seconds: 0.15)
        for startAngle in [60.0, EngineConstants.defaultStartAngle] {
        var memory = EngineMemory()
        var sample: AngleSample?
        var inBand = false
        var nextIdlePoll = 0.0
        var levels: [Double] = []
        var t = 0.0
        while t <= 1 {
            if inBand || t >= nextIdlePoll - 1e-9 {
                sample = AngleSample(angle: trace(t), time: t)
                if !inBand { nextIdlePoll = t + 0.1 }
            }
            var input = EngineInput(now: t)
            input.sample = sample
            input.startAngle = startAngle
            let (m, out) = EffectEngine.step(memory, input)
            memory = m
            inBand = out.inBand
            levels.append(out.level)
            t += 1.0 / 120
        }
        let steps = zip(levels, levels.dropFirst()).map { $1 - $0 }
        XCTAssertLessThan(steps.max()!, 0.15, "start \(startAngle)°")   // per frame
        XCTAssertGreaterThan(levels.max()!, 0.8, "start \(startAngle)°")
        }
    }

    func testSlowCloseReachesFull() {
        let run = replay(duration: 3.5, angle: close(seconds: 3))
        XCTAssertGreaterThanOrEqual(run.maxLevel, 0.95)
    }

    func testLowAngleTypingClearsWithinOneSecond() {
        // Close to 45° then hold while typing.
        let run = replay(duration: 3, angle: close(to: 45, seconds: 0.3)) { t, input in
            if t > 0.6 { input.secondsSinceInput = 0.2 }
        }
        // Typing starts at 0.6 s; the ease-out fade takes about 1 s.
        XCTAssertEqual(run.at(2.0).level, 0)
        XCTAssertFalse(run.at(2.0).windowVisible)
        XCTAssertEqual(run.at(2.0).reason, .dismissed)
    }

    func testHoldingTheLidKeepsTheBlur() {
        // Close to 40° and hold for 30 s with no input: the blur stays at the angle's level the whole time.
        let run = replay(duration: 30, angle: close(to: 40, seconds: 0.3))
        let held = run.at(1).level
        XCTAssertGreaterThan(held, 0.5)
        XCTAssertEqual(run.at(29.9).level, held, accuracy: 0.01)
        XCTAssertTrue(run.at(29.9).windowVisible)
    }

    func testInputDismissesUntilLidClosesFurther() {
        // Hold at 40°, move the cursor at 2 s, stop at 2.5 s, then close further to 25° at 6 s.
        let run = replay(duration: 8, angle: { t in
            t < 6 ? close(to: 40, seconds: 0.3)(t) : max(25, 40 - (t - 6) * 50)
        }) { t, input in
            input.secondsSinceInput = t < 2 ? 1e9 : (t <= 2.5 ? 0 : t - 2.5)
        }
        XCTAssertEqual(run.at(3.5).level, 0)                  // faded after the cursor moved
        XCTAssertEqual(run.at(5.9).level, 0)                  // stays dismissed while the lid is held
        XCTAssertEqual(run.at(5.9).reason, .dismissed)
        XCTAssertGreaterThan(run.at(7.5).level, 0.8)          // closing further brings it back
    }

    func testCustomStartAngleStartsEarlier() {
        let stop = EngineConstants.defaultStartAngle - 1
        let early = replay(duration: 0.6, angle: close(to: stop, seconds: 0.3)) { _, input in input.startAngle = stop + 15 }
        let normal = replay(duration: 0.6, angle: close(to: stop, seconds: 0.3))
        XCTAssertGreaterThan(early.maxLevel, 0.05)
        XCTAssertLessThan(normal.maxLevel, 0.01)
    }

    func testFullAngleStaysBelowStartAngle() {
        // A start angle below the calibrated full angle must not divide by zero or invert the curve.
        let run = replay(duration: 1, angle: close(to: 15, seconds: 0.3)) { _, input in
            input.startAngle = 30; input.fullAngle = 35
        }
        XCTAssertGreaterThan(run.maxLevel, 0.95)
        XCTAssertFalse(run.outputs.contains { $0.out.level.isNaN })
    }

    func testDismissFadeIsEaseOut() {
        // Hold at 40°, then the cursor moves at 2 s: the blur fades on an ease-out curve, visible for a while.
        let run = replay(duration: 5, angle: close(to: 40, seconds: 0.3)) { t, input in
            if t >= 2 { input.secondsSinceInput = 0 }
        }
        let i = run.outputs.firstIndex { $0.out.reason == .dismissed }!
        let (t0, l0) = (run.outputs[i].t, run.outputs[i - 1].out.level)
        let tau = EngineConstants.fadeTimeConstant
        XCTAssertEqual(run.at(t0 + tau).level / l0, exp(-1), accuracy: 0.08)   // fastest at first, then eases
        XCTAssertGreaterThan(run.at(t0 + 0.3).level, 0)                          // still noticeable after 0.3 s
        XCTAssertEqual(run.at(t0 + 7 * tau).level, 0)                            // and gone in about 1 s
    }

    func testWobbleAtThresholdNeverBecomesVisible() {
        // Oscillating ±2° around the start angle at 3 Hz: too little effect to see, so no visible flicker.
        let start = EngineConstants.defaultStartAngle
        let run = replay(duration: 3, angle: { t in start + 1 + 2 * sin(2 * .pi * 3 * t) })
        XCTAssertLessThan(run.maxLevel, 0.02)
    }

    func testWobbleInBandFlipsAtMostThreeTimesPerSecond() {
        // Hand jitter of ±0.3° at 20 Hz while closing slowly must not make the level flicker.
        let base = close(seconds: 3)
        let run = replay(duration: 3.2, angle: { t in base(t) + 0.3 * sin(2 * .pi * 20 * t) })
        var flips = 0
        var lastDir = 0
        for (a, b) in zip(run.outputs, run.outputs.dropFirst()) {
            let d = b.out.level - a.out.level
            let dir = d > 0.01 ? 1 : (d < -0.01 ? -1 : 0)
            if dir != 0 && lastDir != 0 && dir != lastDir { flips += 1 }
            if dir != 0 { lastDir = dir }
        }
        XCTAssertLessThanOrEqual(Double(flips) / 3.2, 3)
    }

    func testSensorDropoutClears() {
        let trace = close(to: 30, seconds: 0.3)
        let run = replay(duration: 2, angle: { t in t < 0.45 ? trace(t) : nil })
        XCTAssertEqual(run.at(0.45 + EngineConstants.staleTimeout + 0.02).level, 0)
        XCTAssertEqual(run.at(1.5).reason, .waitingForSensor)
    }

    func testGarbageValuesClear() {
        let trace = close(to: 30, seconds: 0.3)
        let run = replay(duration: 1, angle: { t in t > 0.4 ? 900 : trace(t) })
        XCTAssertEqual(run.at(0.45).level, 0)
        XCTAssertEqual(run.at(0.45).appState, .unsupported)
    }

    func testOpeningRecedesWithTheLid() {
        // Close to 22°, then open at 100°/s: the blur shrinks in step with the angle, mirroring the close.
        let open: (Double) -> Double = { t in t < 0.6 ? close(to: 22, seconds: 0.3)(t) : 22 + (t - 0.6) * 100 }
        let run = replay(duration: 2, angle: open)
        XCTAssertGreaterThan(run.at(0.6).level, 0.9)
        let start = EngineConstants.defaultStartAngle, full = EngineConstants.defaultFullAngle
        let timeAt = { (angle: Double) in 0.6 + (angle - 22) / 100 }
        // Halfway through the band about half the effect remains.
        let mid = run.at(timeAt((start + full) / 2)).level
        XCTAssertGreaterThan(mid, 0.3)
        XCTAssertLessThan(mid, 0.75)
        // Never rises while opening, and is gone shortly after the lid passes the start angle.
        let opening = run.outputs.filter { $0.t > 0.75 }.map(\.out.level)
        XCTAssertFalse(zip(opening, opening.dropFirst()).contains { $1 > $0 + 1e-9 })
        XCTAssertEqual(run.at(timeAt(start) + 0.15).level, 0)
    }

    func testDisplayGatesHideWindow() {
        let trace = close(to: 22, seconds: 0.3)
        for gate in [{ (s: inout SystemState) in s.reconfiguring = true },
                     { (s: inout SystemState) in s.builtInMirrored = true },
                     { (s: inout SystemState) in s.builtInDisplayID = nil }] {
            let run = replay(duration: 1, angle: trace) { t, input in if t > 0.5 { gate(&input.system) } }
            XCTAssertGreaterThan(run.at(0.49).level, 0.5)
            XCTAssertEqual(run.at(0.51).level, 0)
            XCTAssertFalse(run.at(0.51).windowVisible)
        }
    }

    /// Close the lid to 5°, sleep from 1 s to 2 s (no samples while asleep), wake at 2 s.
    private func sleepCycle(after wake: @escaping (Double) -> Double?) -> Run {
        let closing = close(to: 5, seconds: 0.3)
        return replay(duration: 3, angle: { t in t < 1 ? closing(t) : (t < 2 ? nil : wake(t)) }) { t, input in
            if (1..<2).contains(t) { input.system.systemAwake = false; input.system.displayAwake = false }
            if t >= 2 { input.system.lastWakeTime = 2 }
        }
    }

    func testWakeAfterClosingRecedesWithOpening() {
        // Fresh readings resume 50 ms after wake; the lid opens at 150°/s.
        let run = sleepCycle { t in t < 2.05 ? nil : 5 + (t - 2.05) * 150 }
        XCTAssertGreaterThan(run.at(1.5).level, 0.9)          // held on screen through sleep
        XCTAssertEqual(run.at(1.5).reason, .asleep)
        XCTAssertGreaterThan(run.at(2.02).level, 0.9)         // still there the moment the screen wakes
        let mid = run.at(2.3).level                            // lid at ~42°: partly clear
        XCTAssertGreaterThan(mid, 0.4)
        XCTAssertLessThan(mid, 0.9)
        let opening = run.outputs.filter { $0.t >= 2 }.map(\.out.level)
        XCTAssertFalse(zip(opening, opening.dropFirst()).contains { $1 > $0 + 1e-9 })
        XCTAssertEqual(run.at(2.8).level, 0)                   // gone once the lid passes the start angle
    }

    func testWakeWithoutFreshReadingClears() {
        let run = sleepCycle { _ in nil }
        XCTAssertGreaterThan(run.at(2.02).level, 0.9)
        XCTAssertEqual(run.at(2 + EngineConstants.staleTimeout + 0.02).level, 0)
        XCTAssertEqual(run.at(2.6).reason, .waitingForSensor)
    }

    func testSleepWithOpenLidWakesClear() {
        let run = replay(duration: 3, angle: { t in (1..<2).contains(t) ? nil : 110 }) { t, input in
            if (1..<2).contains(t) { input.system.displayAwake = false }
            if t >= 2 { input.system.lastWakeTime = 2 }
        }
        XCTAssertEqual(run.maxLevel, 0)
    }

    func testWatchdogDismissesAfterVeryLongNearFullHold() {
        let d = EngineConstants.watchdogDuration
        let run = replay(duration: d + 3, angle: close(to: 10, seconds: 0.3))
        XCTAssertGreaterThan(run.at(d - 1).level, 0.9)   // a long hold keeps the blur
        XCTAssertEqual(run.at(d + 2.5).level, 0)          // until the safety net fades it out
        XCTAssertEqual(run.at(d + 2.5).reason, .dismissed)
    }

    func testReduceMotionStillReachesFull() {
        let run = replay(duration: 0.8, angle: close(seconds: 0.4)) { _, input in input.system.reduceMotion = true }
        XCTAssertGreaterThanOrEqual(run.maxLevel, 0.95)
    }

    func testPreviewIgnoresSensorButNotDisplayGates() {
        var input = EngineInput(now: 1)
        input.sensorStatus = .notFound
        input.enabled = false
        input.previewLevel = 0.7
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.level, 0.7)
        input.system.builtInMirrored = true
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.level, 0)
    }

    func testDisabledAndUnsupportedStates() {
        var input = EngineInput(now: 1)
        input.sample = AngleSample(angle: 30, time: 1)
        input.enabled = false
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.appState, .disabled)
        input.enabled = true
        input.sensorStatus = .notFound
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.appState, .unsupported)
    }
}
