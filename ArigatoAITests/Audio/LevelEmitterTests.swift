//
//  LevelEmitterTests.swift
//  ArigatoAITests
//
//  Created by Jose Castell on 2026/05/09.
//

@testable import ArigatoAI
import Testing

@Suite("LevelEmitter throttling")
struct LevelEmitterTests {
    @Test("first call always emits")
    func firstCallEmits() {
        var emitter = LevelEmitter(targetHz: 12)
        let now = ContinuousClock.now
        #expect(emitter.shouldEmit(now: now) == true)
    }

    @Test("calls inside the throttle window are dropped")
    func insideWindowDropped() {
        var emitter = LevelEmitter(targetHz: 12)
        let t0 = ContinuousClock.now
        _ = emitter.shouldEmit(now: t0)
        // 12 Hz => ~83.3 ms interval. 30 ms is well inside.
        let t1 = t0.advanced(by: .milliseconds(30))
        #expect(emitter.shouldEmit(now: t1) == false)
    }

    @Test("calls past the throttle window are accepted")
    func outsideWindowAccepted() {
        var emitter = LevelEmitter(targetHz: 12)
        let t0 = ContinuousClock.now
        _ = emitter.shouldEmit(now: t0)
        let t1 = t0.advanced(by: .milliseconds(100))
        #expect(emitter.shouldEmit(now: t1) == true)
    }

    @Test("rapid stream collapses to roughly target Hz")
    func rapidStreamCollapses() {
        var emitter = LevelEmitter(targetHz: 12)
        let start = ContinuousClock.now
        var emitted = 0
        // Simulate 1 second of 100 Hz samples; expect ~12 emissions.
        for tickMs in stride(from: 0, through: 1000, by: 10) {
            let now = start.advanced(by: .milliseconds(tickMs))
            if emitter.shouldEmit(now: now) {
                emitted += 1
            }
        }
        #expect(emitted >= 10)
        #expect(emitted <= 14)
    }
}
