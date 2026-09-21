import Foundation

/// One precipitation sample at a point in time.
///
/// Buienradar reports a raw 0...255 value per five-minute slot. The documented
/// conversion is `mm/h = 10 ^ ((value - 109) / 32)`.
public struct RainReading: Identifiable, Hashable, Sendable {
    public let timestamp: Date
    public let rawValue: Int

    public init(timestamp: Date, rawValue: Int) {
        self.timestamp = timestamp
        self.rawValue = max(0, rawValue)
    }

    public var id: Date { timestamp }

    public var millimetersPerHour: Double {
        guard rawValue > 0 else { return 0 }
        return pow(10.0, (Double(rawValue) - 109.0) / 32.0)
    }

    public var intensity: RainIntensity {
        RainIntensity(millimetersPerHour: millimetersPerHour)
    }

    public var isRaining: Bool { intensity != .dry }
}
