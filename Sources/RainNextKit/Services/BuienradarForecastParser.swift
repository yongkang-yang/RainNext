// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Decodes Buienradar's `RainHistoryForecast` JSON.
///
/// Every entry carries a real UTC timestamp and a precipitation rate in mm/h,
/// so there is no clock arithmetic to get wrong — this replaced an earlier
/// parser that had to reconstruct dates from bare `HH:mm` strings.
public enum BuienradarForecastParser {
    private struct Payload: Decodable {
        let forecasts: [Entry]
    }

    private struct Entry: Decodable {
        let utcdatetime: String
        let precipitation: Double
        /// Buienradar's raw radar number. Only used for threshold calibration.
        let original: Int?
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        // The feed omits the zone marker; the field name says UTC.
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        return formatter
    }()

    public static func parse(_ data: Data) throws -> [RainReading] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)

        return payload.forecasts
            .compactMap { entry -> RainReading? in
                guard let timestamp = formatter.date(from: entry.utcdatetime) else { return nil }
                return RainReading(
                    timestamp: timestamp,
                    millimetersPerHour: entry.precipitation,
                    rawValue: entry.original
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
