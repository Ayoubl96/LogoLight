import Foundation

/// Gathers the signals from outside (Claude Code's hooks) and tells the logo which one to show. A signal
/// that nothing ends is dropped after `claudeTimeout`, so a hook that never fires (Claude Code killed)
/// can't leave the logo signalling for ever.
@MainActor
public final class SignalCenter {
    public typealias Sleep = @Sendable (Double) async throws -> Void

    private let sleep: Sleep
    private let apply: @MainActor (LogoSignal?) -> Void
    /// What each source says now.
    public private(set) var sources = SignalSources()
    /// What was last handed to `apply`.
    private var shown: LogoSignal?
    private var claudeExpiry: Task<Void, Never>?

    /// How long a Claude Code signal lasts without being renewed or cleared.
    public var claudeTimeout = 30.0 * 60

    /// `apply` is called with the signal to show, or `nil`, each time that changes.
    public init(sleep: @escaping Sleep, apply: @escaping @MainActor (LogoSignal?) -> Void) {
        self.sleep = sleep
        self.apply = apply
    }

    public func handle(_ command: SignalCommand) {
        switch command {
        case .claude(let signal): setClaude(signal)
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

    /// Stops the countdowns, e.g. before quitting. The signals stay as they are.
    public func cancelTimers() {
        claudeExpiry?.cancel()
        claudeExpiry = nil
    }

    private func update() {
        let signal = sources.resolved
        guard signal != shown else { return }
        shown = signal
        apply(signal)
    }
}
