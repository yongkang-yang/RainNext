// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Where Buienradar's radar composite has data.
///
/// Outside this rectangle the feed answers 404 rather than returning zeroes,
/// which is the useful behaviour — "no coverage" never masquerades as "dry".
/// The endpoint is therefore the authority; this box only exists to avoid
/// pointless requests for places that are obviously elsewhere.
///
/// Bounds were measured against the live endpoint, not documented: a 0.5°
/// sweep of western Europe came back a completely filled rectangle, and the
/// four edges were then binary-searched to within 0.004°. Rounded inward so
/// this never claims coverage the feed does not have.
public enum BuienradarCoverage {
    public static let latitudes: ClosedRange<Double> = 49.51...54.80
    public static let longitudes: ClosedRange<Double> = 0.0...10.0

    public static func contains(latitude: Double, longitude: Double) -> Bool {
        latitudes.contains(latitude) && longitudes.contains(longitude)
    }

    public static func contains(_ location: WeatherLocation) -> Bool {
        contains(latitude: location.latitude, longitude: location.longitude)
    }

    /// For UI that has to explain the limit to someone.
    public static let description = "the Netherlands, Belgium and nearby areas"
}
