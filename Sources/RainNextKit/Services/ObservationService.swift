// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol ObservationDataSource: Sendable {
    func fetchObservation(near location: WeatherLocation) async throws -> StationObservation
}

public enum ObservationError: LocalizedError, Equatable {
    case badResponse(Int)
    case malformedPayload
    case noStationsInRange

    public var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Buienradar returned status \(code)."
        case .malformedPayload: return "Could not read Buienradar's observations."
        case .noStationsInRange: return "No weather station nearby."
        }
    }
}

/// Current conditions from Buienradar's documented free JSON feed: 38 KNMI
/// stations, one nationwide payload, so the nearest station is picked locally
/// rather than by asking for a coordinate.
public struct BuienradarObservationService: ObservationDataSource {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchObservation(near location: WeatherLocation) async throws -> StationObservation {
        guard let url = URL(string: "https://data.buienradar.nl/2.0/feed/json") else {
            throw ObservationError.malformedPayload
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ObservationError.badResponse(http.statusCode)
        }

        let stations = try BuienradarFeedParser.parse(data)
        guard let nearest = StationObservation.nearest(
            to: location.latitude, location.longitude, from: stations
        ) else {
            throw ObservationError.noStationsInRange
        }
        return nearest
    }
}

public enum BuienradarFeedParser {
    private struct Feed: Decodable {
        let actual: Actual
        struct Actual: Decodable { let stationmeasurements: [Station] }
    }

    private struct Station: Decodable {
        let stationname: String?
        let regio: String?
        let lat: Double
        let lon: Double
        let timestamp: String
        let weatherdescription: String?
        let iconurl: String?
        let temperature: Double?
        let feeltemperature: Double?
        let windspeedBft: Int?
        let winddirection: String?
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        // Station timestamps are local Dutch time and carry no zone marker.
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        return formatter
    }()

    /// The icon code is the last path component: `.../30x30/aa.png`.
    static func iconCode(from url: String?) -> String? {
        guard let name = url?.split(separator: "/").last?.split(separator: ".").first else { return nil }
        return String(name)
    }

    public static func parse(_ data: Data) throws -> [StationObservation] {
        let feed: Feed
        do {
            feed = try JSONDecoder().decode(Feed.self, from: data)
        } catch {
            throw ObservationError.malformedPayload
        }

        return feed.actual.stationmeasurements.compactMap { station in
            // A station with no condition cannot answer the one question this
            // feed is here for, so it is not a candidate for "nearest".
            guard let code = iconCode(from: station.iconurl) else { return nil }

            return StationObservation(
                stationName: station.stationname ?? station.regio ?? "Unknown",
                region: station.regio ?? "",
                latitude: station.lat,
                longitude: station.lon,
                timestamp: formatter.date(from: station.timestamp) ?? Date(),
                condition: WeatherCondition(iconCode: code),
                isNight: WeatherCondition.isNight(iconCode: code),
                summary: station.weatherdescription ?? "",
                temperature: station.temperature,
                feelsLike: station.feeltemperature,
                windBft: station.windspeedBft,
                windDirection: station.winddirection
            )
        }
    }
}
