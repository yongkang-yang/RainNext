// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the nearest KNMI station is reporting right now.
///
/// This is an observation, not a forecast: it says what the sky is doing, which
/// is the half the precipitation nowcast cannot answer.
public struct StationObservation: Equatable, Sendable {
    public let stationName: String
    public let region: String
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let condition: WeatherCondition
    public let isNight: Bool
    /// Buienradar's own Dutch wording, kept because it is more specific than
    /// the condition it maps to.
    public let summary: String
    public let temperature: Double?
    public let feelsLike: Double?
    public let windBft: Int?
    public let windDirection: String?

    public init(
        stationName: String, region: String, latitude: Double, longitude: Double,
        timestamp: Date, condition: WeatherCondition, isNight: Bool, summary: String,
        temperature: Double?, feelsLike: Double?, windBft: Int?, windDirection: String?
    ) {
        self.stationName = stationName
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.condition = condition
        self.isNight = isNight
        self.summary = summary
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.windBft = windBft
        self.windDirection = windDirection
    }

    public var symbolName: String { condition.symbolName(isNight: isNight) }

    /// Squared great-circle-ish distance, good enough to rank stations across a
    /// country. Longitude is scaled by latitude so it is not over-weighted.
    public func rank(from latitude: Double, _ longitude: Double) -> Double {
        let dLat = self.latitude - latitude
        let dLon = (self.longitude - longitude) * cos(latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    public static func nearest(
        to latitude: Double, _ longitude: Double, from stations: [StationObservation]
    ) -> StationObservation? {
        stations.min { $0.rank(from: latitude, longitude) < $1.rank(from: latitude, longitude) }
    }
}
