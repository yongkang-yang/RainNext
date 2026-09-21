// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One precipitation sample at a point in time.
///
/// Buienradar's JSON feed gives mm/h directly, so that is what this stores.
/// `rawValue` is its undocumented 0...255 radar number, kept only because
/// threshold calibration needs it (BD-108).
public struct RainReading: Identifiable, Hashable, Sendable {
    public let timestamp: Date
    public let millimetersPerHour: Double
    public let rawValue: Int?

    public init(timestamp: Date, millimetersPerHour: Double, rawValue: Int? = nil) {
        self.timestamp = timestamp
        self.millimetersPerHour = max(0, millimetersPerHour)
        self.rawValue = rawValue
    }

    /// Derives mm/h from the raw radar value instead of taking it from the feed.
    public init(timestamp: Date, rawValue: Int) {
        self.init(
            timestamp: timestamp,
            millimetersPerHour: Self.millimetersPerHour(fromRawValue: rawValue),
            rawValue: rawValue
        )
    }

    /// Buienradar's documented conversion. Raw 0 means nothing at all, not
    /// "10^(-109/32) mm/h".
    public static func millimetersPerHour(fromRawValue value: Int) -> Double {
        guard value > 0 else { return 0 }
        return pow(10.0, (Double(value) - 109.0) / 32.0)
    }

    public var id: Date { timestamp }

    public var intensity: RainIntensity {
        RainIntensity(millimetersPerHour: millimetersPerHour)
    }

    public var isRaining: Bool { intensity != .dry }
}
