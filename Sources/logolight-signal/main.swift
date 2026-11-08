import Foundation
import LogoLightCore

// Tells the running LogoLight what to signal on the logo, e.g. from a Claude Code hook:
//   logolight-signal working | waiting | idle
// It does nothing, and still succeeds, when LogoLight isn't running: a hook must never fail
// because the logo isn't there.

guard let command = SignalCommand(arguments: Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data((SignalCommand.usage + "\n").utf8))
    exit(2)
}

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(SignalCommand.notificationName), object: nil,
    userInfo: command.userInfo, deliverImmediately: true)
// The notification is handed over by a run loop pass: give it a moment before exiting.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
