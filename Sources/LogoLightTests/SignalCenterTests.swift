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

/// A center whose timeouts never end by themselves (they sleep for an hour), unless `instant`.
@MainActor
private func makeCenter(_ recorder: Recorder, instant: Bool = false) -> SignalCenter {
    SignalCenter(
        sleep: { seconds in
            await recorder.note(seconds)
            if !instant { try await Task.sleep(for: .seconds(3600)) }
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
}
