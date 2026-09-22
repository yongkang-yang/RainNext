// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Buienradar's hourly rain forecast, which reaches two days out.
///
/// Deliberately not a `RainForecast`. Episodes are derived with thresholds
/// tuned to five-minute radar samples — a ten-minute minimum duration and a
/// fifteen-minute merge gap say nothing about hourly model output, and running
/// it through them would invent episodes rather than find them. The long spans
/// ask simpler questions, so this type answers only those.
public struct HourlyRainForecast: Equatable, Sendable {
    public let location: WeatherLocation
    /// One sample per hour, each the rate expected during the hour it opens.
    public let readings: [RainReading]
    public let fetchedAt: Date

    public init(location: WeatherLocation, readings: [RainReading], fetchedAt: Date) {
        self.location = location
        self.readings = readings.sorted { $0.timestamp < $1.timestamp }
        self.fetchedAt = fetchedAt
    }

    /// What one sample covers.
    public static let slot: TimeInterval = 3600

    /// Whether a payload really is hourly.
    ///
    /// The host answers an unknown product name with the two-hour nowcast, at
    /// 200 rather than with an error, so a typo would look like a working
    /// feature holding five-minute data. Spacing is the only thing that tells
    /// the two apart.
    public static func isHourly(_ readings: [RainReading]) -> Bool {
        let sorted = readings.map(\.timestamp).sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
        guard let smallest = gaps.min() else { return false }
        return smallest >= 30 * 60
    }

    /// The hours `span` covers. The feed opens at the next full hour, so the
    /// hour already under way is included while it is still in the payload.
    public func readings(within span: ForecastSpan, at now: Date) -> [RainReading] {
        readings.filter {
            $0.timestamp > now.addingTimeInterval(-Self.slot)
                && $0.timestamp < now.addingTimeInterval(span.duration)
        }
    }

    public func start(within span: ForecastSpan, at now: Date) -> Date? {
        readings(within: span, at: now).first?.timestamp
    }

    public func end(within span: ForecastSpan, at now: Date) -> Date? {
        readings(within: span, at: now).last?.timestamp.addingTimeInterval(Self.slot)
    }

    /// One line answering "do I need to plan around rain?" for this span.
    public func summary(within span: ForecastSpan, at now: Date) -> String? {
        let window = readings(within: span, at: now)
        guard let last = window.last else { return nil }

        guard let first = window.first(where: \.isRaining) else {
            let through = last.timestamp.addingTimeInterval(Self.slot)
            return "Dry through \(RainPhrasing.boundary(through, relativeTo: now))"
        }

        let peak = window.map(\.millimetersPerHour).max() ?? 0
        return "Rain around \(RainPhrasing.clock(first.timestamp, relativeTo: now))"
            + " · up to \(RainPhrasing.rate(peak))"
    }
}
