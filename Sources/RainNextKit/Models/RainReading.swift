// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One precipitation sample at a point in time.
///
/// Buienradar's JSON feed gives mm/h directly, so that is what this stores.
///
/// `rawValue` is the feed's `original` field, which is also its `value` field —
/// they are always identical. Measured against live data it is simply
/// `mm/h × 20`, on the same 0...100 scale as the feed's own `licht`/`matig`/
/// `zwaar` bands. It is kept because it is finer-grained than `precipitation`,
/// which arrives rounded to one decimal, and threshold calibration wants that
/// resolution (BD-108).
///
/// `precipitation` stays the source of truth even so: it is the provider's own
/// number, whereas the ×20 relation is measured over a narrow range of light
/// rain and should not be extrapolated to a downpour.
public struct RainReading: Identifiable, Hashable, Sendable {
    public let timestamp: Date
    public let millimetersPerHour: Double
    public let rawValue: Int?

    public init(timestamp: Date, millimetersPerHour: Double, rawValue: Int? = nil) {
        self.timestamp = timestamp
        self.millimetersPerHour = max(0, millimetersPerHour)
        self.rawValue = rawValue
    }

    public var id: Date { timestamp }

    public var intensity: RainIntensity {
        RainIntensity(millimetersPerHour: millimetersPerHour)
    }

    public var isRaining: Bool { intensity != .dry }
}
