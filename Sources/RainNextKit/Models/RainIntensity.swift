import Foundation

/// Tuning knobs for turning raw precipitation numbers into "is it raining?" answers.
///
/// These are deliberately in one place: the exact cut-offs are still an open
/// product question (see BD-105) and will want tweaking against real readings.
public enum RainThresholds {
    /// Below this a sample counts as dry. Buienradar's raw 77 is ~0.1 mm/h.
    public static let rainStart: Double = 0.1
    public static let moderate: Double = 0.5
    public static let heavy: Double = 2.0

    /// Buienradar publishes one sample per five minutes.
    public static let sampleInterval: TimeInterval = 5 * 60

    /// A dry gap shorter than this keeps one episode intact instead of
    /// splitting it into two. One dropped sample mid-shower is still one shower.
    public static let episodeMergeGap: TimeInterval = 10 * 60
}

public enum RainIntensity: Int, Comparable, Sendable {
    case dry
    case light
    case moderate
    case heavy

    public init(millimetersPerHour mmh: Double) {
        switch mmh {
        case ..<RainThresholds.rainStart: self = .dry
        case ..<RainThresholds.moderate: self = .light
        case ..<RainThresholds.heavy: self = .moderate
        default: self = .heavy
        }
    }

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
