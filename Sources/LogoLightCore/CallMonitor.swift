import Foundation

/// Watches for the microphone or the camera being in use, as a sign of a call, and tells its owner when
/// that starts and ends. It asks every couple of seconds, and waits for the same answer a few times in a
/// row before it believes a change, so a short blip (a notification sound, an app testing the camera)
/// doesn't flash the logo.
@MainActor
public final class CallMonitor {
    public typealias Sleep = @Sendable (Double) async throws -> Void

    private let microphoneInUse: @MainActor () -> Bool
    private let cameraInUse: @MainActor () -> Bool
    private let sleep: Sleep
    private let onChange: @MainActor (Bool) -> Void
    private var task: Task<Void, Never>?
    private var yes = 0
    private var no = 0

    /// Whether a call is going on, as far as the monitor can tell.
    public private(set) var isInCall = false

    /// Seconds between two looks.
    public var interval = 2.0
    /// How many looks in a row must agree before a call is taken to have started or ended.
    public var looksToStart = 2
    public var looksToEnd = 3

    public init(microphoneInUse: @escaping @MainActor () -> Bool, cameraInUse: @escaping @MainActor () -> Bool,
                sleep: @escaping Sleep, onChange: @escaping @MainActor (Bool) -> Void) {
        self.microphoneInUse = microphoneInUse
        self.cameraInUse = cameraInUse
        self.sleep = sleep
        self.onChange = onChange
    }

    /// Starts looking, and keeps on until `stop()`.
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self, sleep] in
            while !Task.isCancelled {
                guard let self else { return }
                self.look()
                do { try await sleep(self.interval) } catch { return }
            }
        }
    }

    /// Stops looking. A call that was going on is over as far as the owner is concerned.
    public func stop() {
        task?.cancel()
        task = nil
        yes = 0
        no = 0
        if isInCall {
            isInCall = false
            onChange(false)
        }
    }

    /// One look.
    public func look() {
        if microphoneInUse() || cameraInUse() {
            yes += 1
            no = 0
        } else {
            no += 1
            yes = 0
        }
        if !isInCall, yes >= looksToStart {
            isInCall = true
            onChange(true)
        } else if isInCall, no >= looksToEnd {
            isInCall = false
            onChange(false)
        }
    }
}
