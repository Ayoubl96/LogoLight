import CoreGraphics
import Foundation

/// How long the user has been away from the Mac.
public enum UserActivity {
    /// Seconds since the last key press, mouse move, click or scroll.
    public static func idleSeconds() -> Double {
        // `~0` is "any event".
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
