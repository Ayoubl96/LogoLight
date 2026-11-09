import Foundation

/// What the battery says, as a signal. Used with the battery indicator on.
public enum PowerSignal {
    /// Below this charge, with the Mac not plugged in, the logo blinks.
    public static let lowCharge = 0.10
    /// From this charge, plugged in and no longer charging, the battery counts as full.
    public static let fullCharge = 0.99

    /// `.charging` while plugged in and charging, `.fullBattery` once it is full and still plugged in,
    /// `.lowBattery` below 10% and not plugged in, and `nil` otherwise (including when the battery can't
    /// be read, and when plugged in but holding at a level below full, as optimised charging does).
    public static func signal(charge: Double?, isPluggedIn: Bool?, isCharging: Bool?) -> LogoSignal? {
        guard let charge, let isPluggedIn else { return nil }
        if isPluggedIn {
            if isCharging == true { return .charging }
            return charge >= fullCharge ? .fullBattery : nil
        }
        return charge < lowCharge ? .lowBattery : nil
    }
}
