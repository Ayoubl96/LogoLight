import Foundation

/// A request to change what the logo signals, sent by the `logolight-signal` command to the running app
/// (for example from a Claude Code hook).
public enum SignalCommand: Equatable, Sendable {
    /// Claude Code is working (`.working`), is waiting for an answer (`.waiting`) or has nothing to
    /// show (`nil`).
    case claude(LogoSignal?)
    /// Starts a Pomodoro session of this many minutes (1 to 180), or starts it again.
    case pomodoroStart(minutes: Int)
    /// Ends the Pomodoro session, or silences its end-of-session blinking.
    case pomodoroStop

    /// A session lasts this long when the command doesn't say.
    public static let defaultPomodoroMinutes = 25
    public static let pomodoroMinutesRange = 1...180

    /// The name of the distributed notification the command posts and the app listens for.
    public static let notificationName = "app.logolight.signal"

    public static let usage = """
        usage: logolight-signal working | waiting | idle
               logolight-signal pomodoro start [minutes] | stop
        """

    /// Reads the command line's arguments, without the program name. `nil` if they aren't a command.
    public init?(arguments: [String]) {
        let words = arguments.map { $0.lowercased() }
        switch words {
        case ["working"]: self = .claude(.working)
        case ["waiting"]: self = .claude(.waiting)
        case ["idle"]: self = .claude(nil)
        case ["pomodoro", "stop"]: self = .pomodoroStop
        case ["pomodoro", "start"]: self = .pomodoroStart(minutes: Self.defaultPomodoroMinutes)
        default:
            guard words.count == 3, words[0] == "pomodoro", words[1] == "start",
                  let minutes = Int(words[2]), Self.pomodoroMinutesRange.contains(minutes) else { return nil }
            self = .pomodoroStart(minutes: minutes)
        }
    }

    /// What goes in the notification (property-list values only).
    public var userInfo: [String: String] {
        switch self {
        case .claude(let signal): ["command": signal?.rawValue ?? "idle"]
        case .pomodoroStart(let minutes): ["command": "pomodoro-start", "minutes": String(minutes)]
        case .pomodoroStop: ["command": "pomodoro-stop"]
        }
    }

    /// Reads a notification's user info. `nil` if it isn't a command this version knows.
    public init?(userInfo: [AnyHashable: Any]?) {
        guard let name = userInfo?["command"] as? String else { return nil }
        switch name {
        case "pomodoro-start":
            guard let minutes = userInfo?["minutes"] as? String else { return nil }
            self.init(arguments: ["pomodoro", "start", minutes])
        case "pomodoro-stop":
            self.init(arguments: ["pomodoro", "stop"])
        default:
            self.init(arguments: [name])
        }
    }
}
