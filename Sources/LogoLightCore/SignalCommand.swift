import Foundation

/// A request to change what the logo signals, sent by the `logolight-signal` command to the running app
/// (for example from a Claude Code hook).
public enum SignalCommand: Equatable, Sendable {
    /// Claude Code is working (`.working`), is waiting for an answer (`.waiting`) or has nothing to
    /// show (`nil`).
    case claude(LogoSignal?)

    /// The name of the distributed notification the command posts and the app listens for.
    public static let notificationName = "app.logolight.signal"

    public static let usage = "usage: logolight-signal working | waiting | idle"

    /// Reads the command line's arguments, without the program name. `nil` if they aren't a command.
    public init?(arguments: [String]) {
        guard arguments.count == 1 else { return nil }
        switch arguments[0].lowercased() {
        case "working": self = .claude(.working)
        case "waiting": self = .claude(.waiting)
        case "idle": self = .claude(nil)
        default: return nil
        }
    }

    /// What goes in the notification (property-list values only).
    public var userInfo: [String: String] {
        switch self {
        case .claude(let signal): ["command": signal?.rawValue ?? "idle"]
        }
    }

    /// Reads a notification's user info. `nil` if it isn't a command this version knows.
    public init?(userInfo: [AnyHashable: Any]?) {
        guard let name = userInfo?["command"] as? String else { return nil }
        self.init(arguments: [name])
    }
}
