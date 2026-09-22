// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol RainDataSource: Sendable {
    func fetchForecast(for location: WeatherLocation, now: Date) async throws -> RainForecast
    func fetchHourly(for location: WeatherLocation, now: Date) async throws -> HourlyRainForecast
}

public enum RainServiceError: LocalizedError, Equatable {
    case invalidRequest
    case badResponse(Int)
    case emptyPayload
    case malformedPayload
    case outsideCoverage

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Could not build the request."
        case .badResponse(let code): return "Buienradar returned status \(code)."
        case .emptyPayload: return "Buienradar returned no readings."
        case .malformedPayload: return "Could not read Buienradar's response."
        case .outsideCoverage: return "Buienradar only covers \(BuienradarCoverage.description)."
        }
    }
}

/// Precipitation from Buienradar's public graph feeds. No token, no key, and
/// the responses carry UTC timestamps and mm/h directly.
///
/// One host serves several products off the same path, differing only in the
/// name: `RainHistoryForecast` is the two-hour radar nowcast at five-minute
/// steps, `Rain24Hour` is hourly model output. They decode identically, so one
/// parser covers both.
public struct BuienradarRainService: RainDataSource {
    private let session: URLSession
    private let logger: PayloadLogger?

    /// Radar echoes moved forward: five-minute steps, half an hour of history
    /// and a little over two hours ahead.
    private static let nowcastProduct = "RainHistoryForecast"
    /// Hourly model output. Named for a day, but it answers with two — the app
    /// takes what it is given rather than assuming either number.
    private static let hourlyProduct = "Rain24Hour"

    public init(session: URLSession = .shared, logger: PayloadLogger? = PayloadLogger()) {
        self.session = session
        self.logger = logger
    }

    public func fetchForecast(for location: WeatherLocation, now: Date = Date()) async throws -> RainForecast {
        let (data, readings) = try await fetch(Self.nowcastProduct, for: location)

        if let logger {
            Task.detached(priority: .utility) { logger.record(data, location: location, at: now) }
        }

        // The feed reaches further back and further forward than this app cares about.
        let window = ForecastWindow.range(around: now)
        let windowed = readings.filter { window.contains($0.timestamp) }

        return RainForecast(
            location: location,
            readings: windowed.isEmpty ? readings : windowed,
            fetchedAt: now
        )
    }

    public func fetchHourly(for location: WeatherLocation, now: Date = Date()) async throws -> HourlyRainForecast {
        let (_, readings) = try await fetch(Self.hourlyProduct, for: location)

        // An unrecognised product name is answered with the nowcast, at 200
        // rather than with an error. Without this the app would draw
        // five-minute radar under a "48 hours" label and never notice.
        guard HourlyRainForecast.isHourly(readings) else { throw RainServiceError.malformedPayload }

        return HourlyRainForecast(
            location: location,
            readings: readings.filter { $0.timestamp > now.addingTimeInterval(-HourlyRainForecast.slot) },
            fetchedAt: now
        )
    }

    private func fetch(
        _ product: String, for location: WeatherLocation
    ) async throws -> (data: Data, readings: [RainReading]) {
        var components = URLComponents(string: "https://graphdata.buienradar.nl/2.0/forecast/geo/\(product)")
        // Two decimals is all the feed resolves, and it keeps coarse location coarse.
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.2f", location.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.2f", location.longitude)),
        ]
        guard let url = components?.url else { throw RainServiceError.invalidRequest }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // The feed answers 404 for coordinates off the radar composite.
            throw http.statusCode == 404 ? RainServiceError.outsideCoverage
                                         : RainServiceError.badResponse(http.statusCode)
        }

        let readings: [RainReading]
        do {
            readings = try BuienradarForecastParser.parse(data)
        } catch {
            throw RainServiceError.malformedPayload
        }
        guard !readings.isEmpty else { throw RainServiceError.emptyPayload }

        return (data, readings)
    }
}
