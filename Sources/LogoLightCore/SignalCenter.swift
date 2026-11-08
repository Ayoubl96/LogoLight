import Foundation

/// Gathers the signals from outside (Claude Code's hooks, the Pomodoro timer) and tells the logo which one
/// to show. A Claude Code signal that nothing ends is dropped after `claudeTimeout`, so a hook that never
/// fires (Claude Code killed) can't leave the logo signalling for ever.
@MainActor
public final class SignalCenter {
    public typealias Sleep = @Sendable (Double) async throws -> Void

    private let now: @MainActor () -> Date
    private let sleep: Sleep
    private let apply: @MainActor (LogoSignal?) -> Void
    /// What each source says now.
    public private(set) var sources = SignalSources()
    /// What was last handed to `apply`.
    private var shown: LogoSignal?
    private var claudeExpiry: Task<Void, Never>?
    private var pomodoroTask: Task<Void, Never>?
    /// When the session being timed ends, while one is.
    public private(set) var pomodoroEndsAt: Date?

    /// How long a Claude Code signal lasts without being renewed or cleared.
    public var claudeTimeout = 30.0 * 60
    /// How long the logo blinks at the end of a Pomodoro session, if nobody stops it first.
    public var finishedDuration = 20.0

    /// Called when the Pomodoro session starts, ends or is stopped, so a menu can show it.
    public var onPomodoroChange: (@MainActor () -> Void)?

    /// `apply` is called with the signal to show, or `nil`, each time that changes.
    public init(now: @escaping @MainActor () -> Date = { Date() }, sleep: @escaping Sleep,
                apply: @escaping @MainActor (LogoSignal?) -> Void) {
        self.now = now
        self.sleep = sleep
        self.apply = apply
    }

    public func handle(_ command: SignalCommand) {
        switch command {
        case .claude(let signal): setClaude(signal)
        case .pomodoroStart(let minutes): startPomodoro(minutes: minutes)
        case .pomodoroStop: stopPomodoro()
        }
    }

    /// Claude Code's state: `.working`, `.waiting`, or `nil` for nothing. Anything else is ignored.
    /// Saying the same thing again doesn't restart the pattern, only the countdown to dropping it.
    public func setClaude(_ signal: LogoSignal?) {
        guard signal == nil || signal == .working || signal == .waiting else { return }
        claudeExpiry?.cancel()
        claudeExpiry = nil
        sources.claude = signal
        if signal != nil {
            claudeExpiry = Task { [weak self, sleep = self.sleep, timeout = claudeTimeout] in
                do { try await sleep(timeout) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.claudeExpiry = nil
                self.sources.claude = nil
                self.update()
            }
        }
        update()
    }

    /// Starts a Pomodoro session of `minutes` (kept between 1 and 180), or starts it again: the logo
    /// breathes very slowly while it runs, then blinks for `finishedDuration` seconds once it's over.
    public func startPomodoro(minutes: Int) {
        pomodoroTask?.cancel()
        let minutes = min(max(minutes, SignalCommand.pomodoroMinutesRange.lowerBound),
                          SignalCommand.pomodoroMinutesRange.upperBound)
        let focus = Double(minutes) * 60
        pomodoroEndsAt = now().addingTimeInterval(focus)
        sources.pomodoro = .focus
        pomodoroTask = Task { [weak self, sleep = self.sleep, blink = finishedDuration] in
            do { try await sleep(focus) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pomodoroEndsAt = nil
            self.sources.pomodoro = .finished
            self.update()
            self.onPomodoroChange?()
            do { try await sleep(blink) } catch { return }
            guard !Task.isCancelled else { return }
            self.pomodoroTask = nil
            self.sources.pomodoro = nil
            self.update()
            self.onPomodoroChange?()
        }
        update()
        onPomodoroChange?()
    }

    /// Ends the Pomodoro session, or the blinking after it. Does nothing when there is none.
    public func stopPomodoro() {
        guard sources.pomodoro != nil else { return }
        pomodoroTask?.cancel()
        pomodoroTask = nil
        pomodoroEndsAt = nil
        sources.pomodoro = nil
        update()
        onPomodoroChange?()
    }

    /// Seconds left in the session being timed, or `nil` when none is (also while it blinks).
    public var pomodoroRemaining: TimeInterval? {
        pomodoroEndsAt.map { max(0, $0.timeIntervalSince(now())) }
    }

    /// Stops the countdowns, e.g. before quitting. The signals stay as they are.
    public func cancelTimers() {
        claudeExpiry?.cancel()
        claudeExpiry = nil
        pomodoroTask?.cancel()
        pomodoroTask = nil
    }

    private func update() {
        let signal = sources.resolved
        guard signal != shown else { return }
        shown = signal
        apply(signal)
    }
}
