import Foundation
import LogoLightCore

@MainActor
private func settle() async {
    for _ in 0..<500 { await Task.yield() }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200_000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

@MainActor
func signalTests(_ t: TestHarness) async {
    print("\nSignals")

    t.test("every moving signal alternates between dark and lit, with positive durations; a steady one has no cycle") {
        for signal in LogoSignal.allCases {
            let cycle = signal.cycle
            if signal.isSteady {
                t.expect(cycle.isEmpty, "\(signal) is steady")
                continue
            }
            t.expect(cycle.count >= 2, "\(signal) needs at least two steps")
            t.expect(cycle.allSatisfy { $0.fade > 0 && $0.hold >= 0 }, "\(signal) durations")
            t.expect(zip(cycle, cycle.dropFirst() + cycle.prefix(1)).allSatisfy { $0.lit != $1.lit },
                     "\(signal) should alternate")
        }
        t.expectEqual(Set(LogoSignal.allCases.filter(\.isSteady)), [.inCall, .fullBattery])
    }

    t.test("every signal has its own priority") {
        let priorities = LogoSignal.allCases.map(\.priority)
        t.expectEqual(Set(priorities).count, priorities.count)
        t.expectEqual(LogoSignal.allCases.max { $0.priority < $1.priority }, .inCall)
    }

    t.test("a call for attention blinks faster than any effect, and a signal that is just going on is slower") {
        func period(_ cycle: [FadeStep]) -> Double { cycle.reduce(0) { $0 + $1.fade + $1.hold } }
        let fastestEffect = LogoEffect.allCases.filter { $0 != .none }.map { period($0.cycle) }.min() ?? 0
        t.expect(period(LogoSignal.waiting.cycle) < period(LogoEffect.pulse.cycle), "waiting")
        t.expect(period(LogoSignal.finished.cycle) < period(LogoEffect.pulse.cycle), "finished")
        t.expect(fastestEffect > 0)
        t.expect(period(LogoSignal.working.cycle) > period(LogoEffect.breathe.cycle), "working")
        t.expect(period(LogoSignal.focus.cycle) > period(LogoSignal.working.cycle), "focus")
    }

    t.test("a signal's cycle can start with a rise or a fall") {
        for signal in LogoSignal.allCases where !signal.isSteady {
            for lit in [true, false] {
                let turned = signal.cycle(startingLit: lit)
                t.expectEqual(turned.first?.lit, lit)
                let twice = signal.cycle + signal.cycle
                t.expect(signal.cycle.indices.contains { Array(twice[$0..<$0 + turned.count]) == turned },
                         "\(signal) should keep its steps in order")
            }
        }
    }

    t.test("the most important source decides what is shown") {
        t.expectEqual(SignalSources().resolved, nil)
        t.expectEqual(SignalSources(claude: .working).resolved, .working)
        t.expectEqual(SignalSources(pomodoro: .focus).resolved, .focus)
        t.expectEqual(SignalSources(power: .charging).resolved, .charging)
        t.expectEqual(SignalSources(claude: .working, pomodoro: .focus).resolved, .working)
        t.expectEqual(SignalSources(claude: .waiting, pomodoro: .focus, power: .charging).resolved, .waiting)
        t.expectEqual(SignalSources(claude: .working, pomodoro: .finished).resolved, .finished)
        t.expectEqual(SignalSources(pomodoro: .focus, power: .charging).resolved, .focus)
        // A call comes first, so what colleagues see doesn't change.
        t.expectEqual(SignalSources(claude: .waiting, pomodoro: .finished, inCall: true, power: .lowBattery,
                                    reminder: true).resolved, .inCall)
        t.expectEqual(SignalSources(claude: .working, power: .lowBattery).resolved, .lowBattery)
        t.expectEqual(SignalSources(claude: .waiting, reminder: true).resolved, .waiting)
        t.expectEqual(SignalSources(pomodoro: .focus, power: .fullBattery).resolved, .focus)
        t.expectEqual(SignalSources(power: .fullBattery, reminder: true).resolved, .reminder)
    }

    await t.test("a signal plays in place of the effect, which comes back when it ends") {
        let f = Fixture(direct: true)
        f.controller.setEffect(.pulse)
        f.clock.budget = 6
        f.controller.setSignal(.working)
        t.expectEqual(f.controller.signal, .working)
        t.expectEqual(f.controller.effect, .pulse) // the choice is kept
        await settle()
        t.expectEqual(Array(f.clock.slept.prefix(4)), [2.4, 0.6, 3.4, 0.4])

        f.clock.slept.removeAll()
        f.clock.budget = 6
        f.controller.setSignal(nil)
        t.expectEqual(f.controller.signal, nil)
        await settle()
        t.expect(f.clock.slept.contains { $0 == 0.7 || $0 == 1.2 }, "the Pulse should be back: \(f.clock.slept)")
        t.expect(!f.clock.slept.contains(2.4), "not the signal")
        f.controller.restoreNormalLighting()
    }

    await t.test("without an effect, the logo goes back to its brightness when the signal ends") {
        let f = Fixture(direct: true, timeDriven: true)
        f.controller.setBrightness(0.5)
        t.expect(await waitUntil { !f.controller.animator!.isAnimating })
        f.controller.setSignal(.waiting)
        t.expect(f.controller.animator!.isPlaying, "the signal should be playing")
        f.controller.setSignal(nil)
        t.expect(await waitUntil { !f.controller.animator!.isAnimating }, "settles at the brightness")
        t.expect(abs(f.daemon.level - LogoAnimator.level(forBrightness: 0.5)) < 0.03, "level \(f.daemon.level)")
    }

    await t.test("a signal waits for the logo to be on") {
        let f = Fixture(backlightMode: 0, direct: true)
        f.controller.setSignal(.waiting)
        t.expectEqual(f.controller.signal, .waiting)
        t.expect(!f.controller.animator!.isPlaying, "shouldn't play while the logo is off")
        f.clock.budget = 20
        try await f.controller.set(.on)
        t.expect(f.controller.animator!.isPlaying, "should start once the logo is on")
        f.controller.restoreNormalLighting()
    }

    await t.test("a signal needs direct control") {
        let f = Fixture(direct: false)
        f.controller.setSignal(.working)
        t.expectEqual(f.controller.signal, nil)
    }

    await t.test("a Morse message in progress isn't interrupted, and the signal shows once it's done") {
        let f = Fixture(direct: true, timeDriven: true)
        t.expect(f.controller.playMorse("E", loops: false))
        f.controller.setSignal(.working)
        t.expectEqual(f.controller.morse, MorseMessage(text: "E", loops: false))
        t.expect(await waitUntil { f.controller.morse == nil }, "the message should finish")
        t.expectEqual(f.controller.signal, .working)
        t.expect(await waitUntil { f.controller.animator!.isPlaying }, "the signal should play")
        f.controller.setSignal(nil)
        f.controller.restoreNormalLighting()
    }
    await t.test("a call holds the logo at full brightness whatever the slider says, then lets go") {
        let f = Fixture(direct: true, timeDriven: true)
        f.controller.setBrightness(0.3)
        t.expect(await waitUntil { !f.controller.animator!.isAnimating })
        f.controller.setSignal(.inCall)
        t.expect(await waitUntil { !f.controller.animator!.isAnimating }, "settles")
        t.expect(f.daemon.level > 0.97, "lit: \(f.daemon.level)")
        f.controller.setBrightness(0.2)
        t.expect(await waitUntil { !f.controller.animator!.isAnimating })
        t.expect(f.daemon.level > 0.97, "still lit after the slider moved: \(f.daemon.level)")
        f.controller.setSignal(nil)
        t.expect(await waitUntil { !f.controller.animator!.isAnimating }, "settles at the brightness")
        t.expect(abs(f.daemon.level - LogoAnimator.level(forBrightness: 0.2)) < 0.03, "level \(f.daemon.level)")
    }
}
