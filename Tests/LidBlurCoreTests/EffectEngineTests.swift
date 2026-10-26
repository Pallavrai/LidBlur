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
        XCTAssertEqual(run.at(1.6).level, 0)
        XCTAssertFalse(run.at(1.6).windowVisible)
        XCTAssertEqual(run.at(1.6).reason, .recentInput)
    }

    func testHoldAt40WithoutInputClears() {
        let run = replay(duration: 4, angle: close(to: 40, seconds: 0.3))
        XCTAssertGreaterThan(run.at(0.5).level, 0.2)
        XCTAssertGreaterThan(run.at(1.5).level, 0.2)   // a short pause keeps the effect
        // Lid stops at t=0.5; the filter tail and motion window settle (~0.15 s), then still timeout + clear ramp.
        let deadline = 0.5 + 0.15 + EngineConstants.stillTimeout + EngineConstants.clearDuration
        XCTAssertEqual(run.at(deadline).level, 0)
        XCTAssertEqual(run.at(deadline).reason, .still)
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

    func testFadeOutIsGradual() {
        let run = replay(duration: 2, angle: { t in
            t < 0.6 ? close(to: 22, seconds: 0.3)(t) : 22 + (t - 0.6) * 200
        })
        // Midway through the fade the effect is still partly visible, not snapped off.
        let mid = run.at(0.6 + EngineConstants.downMoveWindow + EngineConstants.clearDuration / 2)
        XCTAssertGreaterThan(mid.level, 0.2)
        XCTAssertLessThan(mid.level, 0.9)
    }

    func testHoldBelowHoldAngleKeepsEffect() {
        let run = replay(duration: 3, angle: close(to: 22, seconds: 0.3))
        XCTAssertGreaterThan(run.at(2.5).level, 0.9)
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
        XCTAssertEqual(run.at(1.5).reason, .stale)
    }

    func testGarbageValuesClear() {
        let trace = close(to: 30, seconds: 0.3)
        let run = replay(duration: 1, angle: { t in t > 0.4 ? 900 : trace(t) })
        XCTAssertEqual(run.at(0.45).level, 0)
        XCTAssertEqual(run.at(0.45).appState, .unsupported)
    }

    func testOpeningClearsWithinClearDuration() {
        let run = replay(duration: 2, angle: { t in
            t < 0.6 ? close(to: 22, seconds: 0.3)(t) : 22 + (t - 0.6) * 200
        })
        XCTAssertGreaterThan(run.at(0.6).level, 0.9)
        XCTAssertEqual(run.at(0.6 + EngineConstants.downMoveWindow + EngineConstants.clearDuration + 0.02).level, 0)
    }

    func testDisplayGatesHideWindow() {
        let trace = close(to: 22, seconds: 0.3)
        for gate in [{ (s: inout SystemState) in s.reconfiguring = true },
                     { (s: inout SystemState) in s.builtInMirrored = true },
                     { (s: inout SystemState) in s.builtInDisplayID = nil },
                     { (s: inout SystemState) in s.displayAwake = false }] {
            let run = replay(duration: 1, angle: trace) { t, input in if t > 0.5 { gate(&input.system) } }
            XCTAssertGreaterThan(run.at(0.49).level, 0.5)
            XCTAssertEqual(run.at(0.51).level, 0)
            XCTAssertFalse(run.at(0.51).windowVisible)
        }
    }

    func testStaleSampleAfterWakeStaysClear() {
        // Last reading before sleep was 5°; after wake no fresh sample has arrived yet.
        let run = replay(duration: 1, angle: { t in t < 0.1 ? 5 : nil }) { t, input in
            input.system.lastWakeTime = 0.2
            input.now += 0   // keep sample within staleTimeout so only the wake gate applies
        }
        XCTAssertEqual(run.at(0.3).level, 0)
        XCTAssertEqual(run.at(0.3).reason, .justWoke)
    }

    func testWatchdogDisablesAfterLongHold() {
        let run = replay(duration: 12, angle: close(to: 10, seconds: 0.3))
        let tripped = run.outputs.first { $0.out.requestDisable == .watchdog }
        XCTAssertNotNil(tripped)
        XCTAssertEqual(tripped!.t, 0.5 + EngineConstants.watchdogDuration, accuracy: 0.5)
        XCTAssertEqual(tripped!.out.level, 0)
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
        input.disabledReason = .panic
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.appState, .disabled)
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.reason, .panic)
        input.enabled = true
        input.sensorStatus = .notFound
        XCTAssertEqual(EffectEngine.step(EngineMemory(), input).1.appState, .unsupported)
    }
}
