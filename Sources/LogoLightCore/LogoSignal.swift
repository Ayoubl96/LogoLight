import Foundation

/// A state that comes from outside the logo's own settings (Claude Code working, a Pomodoro
/// session), shown as a pattern in place of the chosen effect for as long as it lasts. When it
/// ends, the effect or the brightness chosen in the menu comes back.
public enum LogoSignal: String, CaseIterable, Sendable {
    /// Microphone or camera in use: the logo stays lit, so anyone behind the screen can see you're in a call.
    case inCall
    /// Asks for attention: Claude Code is waiting for an answer.
    case waiting
    /// Asks for attention: something the user asked to be reminded of, while they're away from the Mac.
    case reminder
    /// Asks for attention: a Pomodoro session is over.
    case finished
    /// The battery is nearly empty and the Mac isn't charging.
    case lowBattery
    /// Claude Code is working.
    case working
    /// A Pomodoro session is running.
    case focus
    /// The battery is full and the Mac is plugged in: you can unplug it. The logo stays lit.
    case fullBattery
    /// The Mac is charging.
    case charging

    /// Which wins when several are active at once: the larger one. A call comes first, so what
    /// colleagues see doesn't change, then what needs an answer, then what is just going on.
    public var priority: Int {
        switch self {
        case .inCall: 8
        case .waiting: 7
        case .reminder: 6
        case .finished: 5
        case .lowBattery: 4
        case .working: 3
        case .focus: 2
        case .fullBattery: 1
        case .charging: 0
        }
    }

    /// Whether the logo is held lit, at full brightness, instead of moving: the signal has no cycle.
    public var isSteady: Bool {
        self == .inCall || self == .fullBattery
    }

    /// One cycle of the pattern, repeated while the signal lasts. Rises are longer than falls, as
    /// in the effects, and a call for attention is a quick blink that can't be taken for an effect.
    public var cycle: [FadeStep] {
        switch self {
        case .inCall, .fullBattery:
            []
        case .waiting, .finished:
            [FadeStep(lit: false, fade: 0.12, hold: 0.28), FadeStep(lit: true, fade: 0.12, hold: 0.5)]
        case .reminder:
            // Two quick blinks, then a rest: harder to ignore than a plain blink, from across a room.
            [FadeStep(lit: false, fade: 0.12, hold: 0.12), FadeStep(lit: true, fade: 0.12, hold: 0.12),
             FadeStep(lit: false, fade: 0.12, hold: 0.12), FadeStep(lit: true, fade: 0.12, hold: 1.1)]
        case .lowBattery:
            // A slow, urgent blink: on for a moment, long dark.
            [FadeStep(lit: false, fade: 0.3, hold: 1.4), FadeStep(lit: true, fade: 0.3, hold: 0.4)]
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
    /// Whether the microphone or the camera is in use.
    public var inCall = false
    /// From the battery, with the battery indicator on: `.charging`, `.fullBattery` or `.lowBattery`.
    public var power: LogoSignal?
    /// Whether a reminder is asking for attention.
    public var reminder = false

    public init(claude: LogoSignal? = nil, pomodoro: LogoSignal? = nil, inCall: Bool = false,
                power: LogoSignal? = nil, reminder: Bool = false) {
        self.claude = claude
        self.pomodoro = pomodoro
        self.inCall = inCall
        self.power = power
        self.reminder = reminder
    }

    /// The signal to show, if any.
    public var resolved: LogoSignal? {
        [claude, pomodoro, inCall ? .inCall : nil, power, reminder ? .reminder : nil]
            .compactMap { $0 }
            .max { $0.priority < $1.priority }
    }
}
