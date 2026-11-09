import EventKit
import Foundation
import LogoLightCore

/// Asks the logo to remind you of calendar events that are about to start. It only looks at the events
/// the Calendar app already has (including accounts like Google Calendar added to it), once the user
/// has allowed it. The logo then blinks only if you've been away from the Mac (see `SignalCenter.remind`).
@MainActor
final class CalendarReminders {
    /// How long before an event starts the reminder goes off.
    static let lead: TimeInterval = 5 * 60

    private let store = EKEventStore()
    private var task: Task<Void, Never>?
    /// Events already reminded of (their identifier and start), so each one blinks once.
    private var reminded: Set<String> = []
    private let onEvent: @MainActor () -> Void

    init(onEvent: @escaping @MainActor () -> Void) {
        self.onEvent = onEvent
    }

    /// Whether the user has already allowed access to the calendar.
    var isAllowed: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Starts looking, asking for access first if needed (macOS shows its own prompt). Returns `false`
    /// when access isn't given.
    func start() async -> Bool {
        guard task == nil else { return true }
        var granted = isAllowed
        if !granted { granted = (try? await store.requestFullAccessToEvents()) ?? false }
        guard granted else { return false }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.look()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        return true
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Reminds of the events that start within the lead time and that haven't been reminded of.
    private func look() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(Self.lead + 60),
                                                 calendars: nil)
        for event in store.events(matching: predicate)
        where !event.isAllDay && event.startDate.timeIntervalSince(now) <= Self.lead {
            let key = "\(event.eventIdentifier ?? event.title ?? "")|\(event.startDate.timeIntervalSince1970)"
            if reminded.insert(key).inserted { onEvent() }
        }
    }
}
