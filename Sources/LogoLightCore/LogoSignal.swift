import Foundation

/// A state that comes from outside the logo's own settings (Claude Code working, a Pomodoro
/// session), shown as a pattern in place of the chosen effect for as long as it lasts. When it
/// ends, the effect or the brightness chosen in the menu comes back.
public enum LogoSignal: String, CaseIterable, Sendable {
    /// Asks for attention: Claude Code is waiting for an answer.
    case waiting
    /// Asks for attention: a Pomodoro session is over.
    case finished
    /// Claude Code is working.
    case working
    /// A Pomodoro session is running.
    case focus
    /// The battery indicator is on and the Mac is charging.
    case charging

    /// Which wins when several are active at once: the larger one. Something that needs an
    /// answer beats something that is just going on.
    public var priority: Int {
        switch self {
        case .waiting: 4
        case .finished: 3
        case .working: 2
        case .focus: 1
        case .charging: 0
        }
    }

    /// One cycle of the pattern, repeated while the signal lasts. Rises are longer than falls, as
    /// in the effects, and a call for attention is a quick blink that can't be taken for an effect.
    public var cycle: [FadeStep] {
        switch self {
        case .waiting, .finished:
            [FadeStep(lit: false, fade: 0.12, hold: 0.28), FadeStep(lit: true, fade: 0.12, hold: 0.5)]
        case .working:
            // Slower than Breathe, so a long task looks calm rather than busy.
            [FadeStep(lit: false, fade: 2.4, hold: 0.6), FadeStep(lit: true, fade: 3.4, hold: 0.4)]
        case .focus:
            // Very slow: about eight seconds a breath, to sit at the edge of notice.
            [FadeStep(lit: false, fade: 3.2, hold: 0.8), FadeStep(lit: true, fade: 4.2, hold: 0.8)]
        case .charging:
            // A soft, steady pulse, quicker than a breath.
            [FadeStep(lit: false, fade: 0.9, hold: 0.1), FadeStep(lit: true, fade: 1.5, hold: 0.3)]
        }
    }

    /// The cycle, turned to start with its first step toward lit (`true`) or toward dark.
    public func cycle(startingLit lit: Bool) -> [FadeStep] {
        let steps = cycle
        let start = steps.firstIndex { $0.lit == lit } ?? 0
        return Array(steps[start...] + steps[..<start])
    }
}

/// What each source of signals says right now. The logo shows the most important one.
public struct SignalSources: Equatable, Sendable {
    /// From Claude Code's hooks: `.working` or `.waiting`.
    public var claude: LogoSignal?
    /// From the Pomodoro timer: `.focus` or `.finished`.
    public var pomodoro: LogoSignal?
    /// Whether the Mac is charging with the battery indicator on.
    public var charging = false

    public init(claude: LogoSignal? = nil, pomodoro: LogoSignal? = nil, charging: Bool = false) {
        self.claude = claude
        self.pomodoro = pomodoro
        self.charging = charging
    }

    /// The signal to show, if any.
    public var resolved: LogoSignal? {
        [claude, pomodoro, charging ? .charging : nil]
            .compactMap { $0 }
            .max { $0.priority < $1.priority }
    }
}
