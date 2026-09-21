// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol RainDataSource: Sendable {
    func fetchForecast(for location: WeatherLocation, now: Date) async throws -> RainForecast
}

public enum RainServiceError: LocalizedError, Equatable {
    case invalidRequest
    case badResponse(Int)
    case emptyPayload
    case malformedPayload

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Could not build the request."
        case .badResponse(let code): return "Buienradar returned status \(code)."
        case .emptyPayload: return "Buienradar returned no readings."
        case .malformedPayload: return "Could not read Buienradar's response."
        }
    }
}

/// Precipitation nowcast from Buienradar's public `RainHistoryForecast` feed.
/// No token, no key, and the response carries UTC timestamps and mm/h directly.
public struct BuienradarRainService: RainDataSource {
    private let session: URLSession
    private let logger: PayloadLogger?

    public init(session: URLSession = .shared, logger: PayloadLogger? = PayloadLogger()) {
        self.session = session
        self.logger = logger
    }

    public func fetchForecast(for location: WeatherLocation, now: Date = Date()) async throws -> RainForecast {
        var components = URLComponents(string: "https://graphdata.buienradar.nl/2.0/forecast/geo/RainHistoryForecast")
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
            throw RainServiceError.badResponse(http.statusCode)
        }

        let readings: [RainReading]
        do {
            readings = try BuienradarForecastParser.parse(data)
        } catch {
            throw RainServiceError.malformedPayload
        }
        guard !readings.isEmpty else { throw RainServiceError.emptyPayload }

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
}
