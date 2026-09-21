// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Every number that decides what the app says, in one place.
///
/// Two separate floors on purpose. `episodeFloor` decides what exists at all —
/// it stays low so drizzle is still visible on the timeline. `announceFloor`
/// decides what earns a countdown in the menu bar, because a countdown that
/// expires with nothing falling outside is how people stop trusting the number.
/// Missing a trace of drizzle costs far less than one confident false alarm.
///
/// These are still estimates, not measurements — see BD-108. `PayloadLogger`
/// collects the raw data to replace them with.
public enum RainThresholds {
    /// Below this a sample counts as dry. 0.1 mm/h is the smallest rate the
    /// feed reports at all — it quantises to 0.05 steps and rounds what it
    /// publishes to one decimal.
    public static let episodeFloor: Double = 0.1

    /// An episode whose peak stays under this never reaches the menu bar.
    public static let announceFloor: Double = 0.4

    public static let moderate: Double = 0.5
    public static let heavy: Double = 2.5

    /// One isolated wet sample is usually radar clutter, or a shower clipping
    /// the corner of the grid cell — not rain that will land on anyone.
    public static let minimumEpisodeDuration: TimeInterval = 10 * 60

    /// Dutch showers arrive in trains with short dry slots between them.
    /// Bridging two of them keeps one weather event as one episode, instead of
    /// flapping the menu bar between "rain in 5m" and "rain in 20m".
    public static let episodeMergeGap: TimeInterval = 15 * 60

    /// Nominal spacing. Buienradar usually sends one sample per five minutes,
    /// but payloads do drop slots, so this is only a fallback for the last
    /// sample in a series.
    public static let sampleInterval: TimeInterval = 5 * 60
}

public enum RainIntensity: Int, Comparable, Sendable {
    case dry
    case light
    case moderate
    case heavy

    public init(millimetersPerHour mmh: Double) {
        switch mmh {
        case ..<RainThresholds.episodeFloor: self = .dry
        case ..<RainThresholds.moderate: self = .light
        case ..<RainThresholds.heavy: self = .moderate
        default: self = .heavy
        }
    }

    /// The user's words, deliberately not the forecaster's: meteorology calls
    /// 2.5 mm/h the start of *moderate* rain, but colloquially that is already
    /// a soaking.
    public var label: String {
        switch self {
        case .dry: return "Dry"
        case .light: return "Light rain"
        case .moderate: return "Rain"
        case .heavy: return "Heavy rain"
        }
    }

    public static func < (lhs: RainIntensity, rhs: RainIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
