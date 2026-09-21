import Foundation

public protocol RainDataSource: Sendable {
    func fetchForecast(for location: WeatherLocation, now: Date) async throws -> RainForecast
}

public enum RainServiceError: LocalizedError, Equatable {
    case invalidRequest
    case badResponse(Int)
    case emptyPayload

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Could not build the request."
        case .badResponse(let code): return "Buienradar returned status \(code)."
        case .emptyPayload: return "Buienradar returned no readings."
        }
    }
}

/// Two-hour precipitation nowcast straight from Buienradar's gpsgadget endpoint.
public struct BuienradarRainService: RainDataSource {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchForecast(for location: WeatherLocation, now: Date = Date()) async throws -> RainForecast {
        var components = URLComponents(string: "https://gpsgadget.buienradar.nl/data/raintext")
        // Two decimals is all the endpoint uses, and it keeps coarse location coarse.
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

        let payload = String(decoding: data, as: UTF8.self)
        let readings = BuienradarParser.parse(payload, reference: now)
        guard !readings.isEmpty else { throw RainServiceError.emptyPayload }

        return RainForecast(location: location, readings: readings, fetchedAt: now)
    }
}
