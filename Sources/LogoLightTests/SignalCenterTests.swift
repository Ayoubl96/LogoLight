import Foundation
import LogoLightCore

/// Notes what the center asked the logo to show, and how long it waited for each timeout.
@MainActor
private final class Recorder {
    var shown: [LogoSignal?] = []
    var sleeps: [Double] = []
    func note(_ seconds: Double) { sleeps.append(seconds) }
}

@MainActor
private func settle() async {
    for _ in 0..<200 { await Task.yield() }
}

/// How long the user has been away from the Mac.
@MainActor
private final class FakeIdle {
    var seconds = 0.0
}

/// Stands in for the microphone and the camera.
@MainActor
private final class FakeSensors {
    var microphone = false
    var camera = false
}

/// A stand-in for the time of day.
@MainActor
private final class FakeNow {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

/// A center whose timeouts never end by themselves (they sleep for an hour), unless `instant`, or a
/// wait is one of `instantFor` seconds.
@MainActor
private func makeCenter(_ recorder: Recorder, instant: Bool = false, instantFor: Set<Double> = [],
                        now: FakeNow = FakeNow(), idle: FakeIdle = FakeIdle()) -> SignalCenter {
    SignalCenter(
        now: { now.date },
        idleSeconds: { idle.seconds },
        sleep: { seconds in
            await recorder.note(seconds)
            if !instant, !instantFor.contains(seconds) { try await Task.sleep(for: .seconds(3600)) }
        },
        apply: { recorder.shown.append($0) })
}

@MainActor
func signalCenterTests(_ t: TestHarness) async {
    print("\nSignal center")

    t.test("reads the command line, and the notification it makes") {
        t.expectEqual(SignalCommand(arguments: ["working"]), .claude(.working))
        t.expectEqual(SignalCommand(arguments: ["Waiting"]), .claude(.waiting))
        t.expectEqual(SignalCommand(arguments: ["idle"]), .claude(nil))
        t.expectEqual(SignalCommand(arguments: []), nil)
        t.expectEqual(SignalCommand(arguments: ["working", "now"]), nil)
        t.expectEqual(SignalCommand(arguments: ["dancing"]), nil)
        for command in [SignalCommand.claude(.working), .claude(.waiting), .claude(nil)] {
            t.expectEqual(SignalCommand(userInfo: command.userInfo), command)
        }
        t.expectEqual(SignalCommand(userInfo: nil), nil)
        t.expectEqual(SignalCommand(userInfo: ["command": "dancing"]), nil)
        t.expectEqual(SignalCommand(userInfo: ["other": "working"]), nil)
    }

    t.test("reads the Pomodoro commands") {
        t.expectEqual(SignalCommand(arguments: ["pomodoro", "start"]), .pomodoroStart(minutes: 25))
        t.expectEqual(SignalCommand(arguments: ["pomodoro", "start", "50"]), .pomodoroStart(minutes: 50))
        t.expectEqual(SignalCommand(arguments: ["Pomodoro", "Stop"]), .pomodoroStop)
        t.expectEqual(SignalCommand(arguments: ["pomodoro"]), nil)
        t.expectEqual(SignalCommand(arguments: ["pomodoro", "start", "0"]), nil)
        t.expectEqual(SignalCommand(arguments: ["pomodoro", "start", "181"]), nil)
        t.expectEqual(SignalCommand(arguments: ["pomodoro", "start", "soon"]), nil)
        t.expectEqual(SignalCommand(arguments: ["pomodoro", "start", "5", "6"]), nil)
        for command in [SignalCommand.pomodoroStart(minutes: 25), .pomodoroStart(minutes: 90), .pomodoroStop] {
            t.expectEqual(SignalCommand(userInfo: command.userInfo), command)
        }
        t.expectEqual(SignalCommand(userInfo: ["command": "pomodoro-start"]), nil)
        t.expectEqual(SignalCommand(userInfo: ["command": "pomodoro-start", "minutes": "9999"]), nil)
    }

    t.test("shows what Claude Code says, and clears it") {
        let r = Recorder()
        let center = makeCenter(r)
        center.handle(.claude(.working))
        center.handle(.claude(.waiting))
        center.handle(.claude(nil))
        t.expect(r.shown == [.working, .waiting, nil], "\(r.shown)")
        center.cancelTimers()
    }

    await t.test("saying the same thing again doesn't restart the pattern") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setClaude(.working)
        center.setClaude(.working)
        center.setClaude(.working)
        t.expect(r.shown == [.working], "\(r.shown)")
        await settle()
        t.expectEqual(r.sleeps, [1800, 1800, 1800]) // the countdown starts again each time
        center.cancelTimers()
    }

    t.test("clearing with nothing showing does nothing") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setClaude(nil)
        t.expect(r.shown.isEmpty, "\(r.shown)")
    }

    t.test("only working and waiting come from Claude Code") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setClaude(.focus)
        center.setClaude(.charging)
        t.expect(r.shown.isEmpty, "\(r.shown)")
        t.expectEqual(center.sources.claude, nil)
    }

    await t.test("drops a signal nothing has ended, after the timeout") {
        let r = Recorder()
        let center = makeCenter(r, instant: true)
        center.claudeTimeout = 42
        center.setClaude(.working)
        await settle()
        t.expectEqual(r.sleeps, [42])
        t.expect(r.shown == [.working, nil], "\(r.shown)")
    }

    await t.test("a new signal takes over the countdown of the old one") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setClaude(.working)
        await settle()
        center.setClaude(.waiting)
        center.setClaude(nil)
        await settle()
        t.expect(r.shown == [.working, .waiting, nil], "\(r.shown)")
        center.cancelTimers()
    }
    await t.test("a Pomodoro session breathes slowly, then blinks, then ends") {
        let r = Recorder()
        let center = makeCenter(r, instant: true)
        center.finishedDuration = 20
        var changes = 0
        center.onPomodoroChange = { changes += 1 }
        center.startPomodoro(minutes: 25)
        await settle()
        t.expectEqual(r.sleeps, [1500, 20])
        t.expect(r.shown == [.focus, .finished, nil], "\(r.shown)")
        t.expectEqual(changes, 3) // started, over, blinking done
        t.expectEqual(center.pomodoroRemaining, nil)
    }

    await t.test("stopping the session puts the logo back") {
        let r = Recorder()
        let center = makeCenter(r)
        var changes = 0
        center.onPomodoroChange = { changes += 1 }
        center.startPomodoro(minutes: 25)
        t.expect(center.pomodoroRemaining != nil)
        center.stopPomodoro()
        t.expect(r.shown == [.focus, nil], "\(r.shown)")
        t.expectEqual(center.pomodoroRemaining, nil)
        t.expectEqual(changes, 2)
        center.stopPomodoro() // nothing to stop
        t.expectEqual(changes, 2)
    }

    await t.test("a command can start and stop the session") {
        let r = Recorder()
        let center = makeCenter(r)
        center.handle(.pomodoroStart(minutes: 10))
        center.handle(.pomodoroStop)
        t.expect(r.shown == [.focus, nil], "\(r.shown)")
        await settle()
        t.expectEqual(r.sleeps, [600])
    }

    await t.test("a session is kept between one minute and three hours") {
        let r = Recorder()
        let center = makeCenter(r)
        center.startPomodoro(minutes: 0)
        await settle()
        center.startPomodoro(minutes: 500)
        await settle()
        t.expectEqual(r.sleeps, [60, 10800])
        center.cancelTimers()
    }

    await t.test("the time left counts down") {
        let r = Recorder()
        let now = FakeNow()
        let center = makeCenter(r, now: now)
        t.expectEqual(center.pomodoroRemaining, nil)
        center.startPomodoro(minutes: 25)
        t.expectEqual(center.pomodoroRemaining, 1500)
        now.date.addTimeInterval(600)
        t.expectEqual(center.pomodoroRemaining, 900)
        now.date.addTimeInterval(5000)
        t.expectEqual(center.pomodoroRemaining, 0)
        center.cancelTimers()
    }

    await t.test("starting again replaces the session, without restarting the pattern") {
        let r = Recorder()
        let center = makeCenter(r)
        center.startPomodoro(minutes: 25)
        center.startPomodoro(minutes: 10)
        await settle()
        t.expectEqual(r.sleeps.sorted(), [600, 1500]) // the first only got as far as starting its wait
        t.expect(r.shown == [.focus], "\(r.shown)")
        t.expectEqual(center.pomodoroRemaining, 600)
        center.cancelTimers()
    }

    await t.test("Claude Code waiting for an answer comes before the session, which comes back after") {
        let r = Recorder()
        let center = makeCenter(r)
        center.startPomodoro(minutes: 25)
        center.setClaude(.waiting)
        center.setClaude(nil)
        t.expect(r.shown == [.focus, .waiting, .focus], "\(r.shown)")
        center.cancelTimers()
    }

    await t.test("a finished session comes before Claude Code working, which comes back after the blinking") {
        let r = Recorder()
        let center = makeCenter(r, instantFor: [60, 20])
        center.setClaude(.working)
        center.startPomodoro(minutes: 1)
        await settle()
        t.expect(r.shown == [.working, .finished, .working], "\(r.shown)")
        center.cancelTimers()
    }
    t.test("the battery's signal comes below Claude Code and the session, and goes with it") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setPower(.charging)
        center.setPower(.charging) // nothing new
        center.startPomodoro(minutes: 25)
        center.setClaude(.working)
        center.setClaude(nil)
        center.stopPomodoro()
        center.setPower(nil)
        t.expect(r.shown == [.charging, .focus, .working, .focus, .charging, nil], "\(r.shown)")
        center.cancelTimers()
    }

    t.test("only the battery's signals come from the battery, and a low battery beats Claude Code working") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setPower(.working)
        center.setPower(.inCall)
        t.expect(r.shown.isEmpty, "\(r.shown)")
        center.setClaude(.working)
        center.setPower(.lowBattery)
        center.setPower(.fullBattery)
        t.expect(r.shown == [.working, .lowBattery, .working], "\(r.shown)")
        center.cancelTimers()
    }

    t.test("a call comes before everything, and the logo goes back when it ends") {
        let r = Recorder()
        let center = makeCenter(r)
        center.setClaude(.waiting)
        center.setInCall(true)
        center.setInCall(true) // nothing new
        center.setPower(.lowBattery)
        center.setInCall(false)
        t.expect(r.shown == [.waiting, .inCall, .waiting], "\(r.shown)")
        center.cancelTimers()
    }

    t.test("works out the battery's signal") {
        func signal(_ charge: Double?, plugged: Bool?, charging: Bool?) -> LogoSignal? {
            PowerSignal.signal(charge: charge, isPluggedIn: plugged, isCharging: charging)
        }
        t.expectEqual(signal(0.5, plugged: true, charging: true), .charging)
        t.expectEqual(signal(1, plugged: true, charging: false), .fullBattery)
        t.expectEqual(signal(0.995, plugged: true, charging: false), .fullBattery)
        t.expectEqual(signal(0.8, plugged: true, charging: false), nil) // holding below full
        t.expectEqual(signal(0.05, plugged: false, charging: false), .lowBattery)
        t.expectEqual(signal(0.099, plugged: false, charging: false), .lowBattery)
        t.expectEqual(signal(0.10, plugged: false, charging: false), nil)
        t.expectEqual(signal(0.05, plugged: true, charging: true), .charging) // plugged in: not low
        t.expectEqual(signal(0.5, plugged: false, charging: false), nil)
        t.expectEqual(signal(nil, plugged: true, charging: true), nil)
        t.expectEqual(signal(0.5, plugged: nil, charging: true), nil)
    }

    await t.test("a reminder blinks only when the user has been away") {
        let r = Recorder()
        let idle = FakeIdle()
        let center = makeCenter(r, idle: idle)
        idle.seconds = 30
        center.remind()
        t.expect(r.shown.isEmpty, "the user is using the Mac: \(r.shown)")
        t.expect(!center.sources.reminder)
        idle.seconds = 300
        center.remind()
        center.remind() // already blinking
        t.expect(r.shown == [.reminder], "\(r.shown)")
        center.stopReminder()
        t.expect(r.shown == [.reminder, nil], "\(r.shown)")
        center.stopReminder()
        t.expect(r.shown == [.reminder, nil], "\(r.shown)")
    }

    await t.test("a reminder stops when the user comes back") {
        let r = Recorder()
        let idle = FakeIdle()
        idle.seconds = 300
        let center = SignalCenter(
            idleSeconds: { r.sleeps.count >= 3 ? 1 : idle.seconds },
            sleep: { seconds in await r.note(seconds) },
            apply: { r.shown.append($0) })
        center.remind()
        await settle()
        t.expectEqual(r.sleeps, [2, 2, 2])
        t.expect(r.shown == [.reminder, nil], "\(r.shown)")
    }

    await t.test("a reminder nobody answers stops after its time") {
        let r = Recorder()
        let idle = FakeIdle()
        idle.seconds = 300
        let center = makeCenter(r, instantFor: [2], idle: idle)
        center.reminderDuration = 6
        center.remind()
        await settle()
        t.expectEqual(r.sleeps, [2, 2, 2])
        t.expect(r.shown == [.reminder, nil], "\(r.shown)")
    }

    t.test("a reminder is read from the command line") {
        t.expectEqual(SignalCommand(arguments: ["remind"]), .remind)
        t.expectEqual(SignalCommand(arguments: ["remind", "now"]), nil)
        t.expectEqual(SignalCommand(userInfo: SignalCommand.remind.userInfo), .remind)
    }

    t.test("a call is believed after a couple of looks, and over after a few without") {
        let sensors = FakeSensors()
        var changes: [Bool] = []
        let monitor = CallMonitor(microphoneInUse: { sensors.microphone }, cameraInUse: { sensors.camera },
                                  sleep: { _ in }, onChange: { changes.append($0) })
        sensors.microphone = true
        monitor.look()
        t.expect(changes.isEmpty, "one look isn't enough")
        monitor.look()
        t.expect(changes == [true] && monitor.isInCall, "\(changes)")
        sensors.microphone = false
        monitor.look(); monitor.look()
        t.expect(changes == [true], "still in the call")
        monitor.look()
        t.expect(changes == [true, false] && !monitor.isInCall, "\(changes)")
    }

    t.test("a blip doesn't make a call, and a pause doesn't end one") {
        let sensors = FakeSensors()
        var changes: [Bool] = []
        let monitor = CallMonitor(microphoneInUse: { sensors.microphone }, cameraInUse: { sensors.camera },
                                  sleep: { _ in }, onChange: { changes.append($0) })
        sensors.microphone = true
        monitor.look()
        sensors.microphone = false
        monitor.look()
        sensors.microphone = true
        monitor.look()
        t.expect(changes.isEmpty, "\(changes)")
        monitor.look() // two in a row now
        t.expect(changes == [true], "\(changes)")
        sensors.microphone = false
        monitor.look(); monitor.look()
        sensors.camera = true // the camera counts as well
        monitor.look()
        sensors.camera = false
        monitor.look(); monitor.look()
        t.expect(changes == [true], "the pause was short: \(changes)")
    }

    t.test("the camera alone is a call, and stopping the monitor ends it") {
        let sensors = FakeSensors()
        var changes: [Bool] = []
        let monitor = CallMonitor(microphoneInUse: { sensors.microphone }, cameraInUse: { sensors.camera },
                                  sleep: { _ in }, onChange: { changes.append($0) })
        sensors.camera = true
        monitor.look(); monitor.look()
        t.expect(changes == [true], "\(changes)")
        monitor.stop()
        t.expect(changes == [true, false] && !monitor.isInCall, "\(changes)")
        monitor.stop()
        t.expect(changes == [true, false], "\(changes)")
    }

    await t.test("the monitor looks at once when it starts") {
        let sensors = FakeSensors()
        sensors.camera = true
        var looks = 0
        let monitor = CallMonitor(microphoneInUse: { looks += 1; return sensors.microphone },
                                  cameraInUse: { sensors.camera },
                                  sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, onChange: { _ in })
        monitor.start()
        monitor.start() // already running
        await settle()
        t.expectEqual(looks, 1)
        monitor.stop()
    }
}
