// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

/// Serves canned responses so the service's error mapping and windowing can be
/// tested without the network.
final class StubURLProtocol: URLProtocol {
    static var respond: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.respond?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RainServiceTests: XCTestCase {
    private var service: BuienradarRainService!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        // Logger off: tests must not write into Application Support.
        service = BuienradarRainService(session: URLSession(configuration: configuration), logger: nil)
    }

    override func tearDown() {
        StubURLProtocol.respond = nil
    }

    private func payload(offsetsInMinutes: [Int], from now: Date, rate: Double = 0) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt

        let entries = offsetsInMinutes.map { minutes in
            let stamp = formatter.string(from: now.addingTimeInterval(Double(minutes) * 60))
            return #"{"utcdatetime":"\#(stamp)","precipitation":\#(rate),"original":0}"#
        }
        return Data("{\"forecasts\":[\(entries.joined(separator: ","))]}".utf8)
    }

    func testMaps404ToCoverage() async {
        // The feed answers 404 off the radar composite, which is a different
        // problem from a server fault and needs a different message.
        StubURLProtocol.respond = { _ in (404, Data()) }
        await assert(throws: .outsideCoverage)
    }

    func testMapsOtherFailuresToBadResponse() async {
        StubURLProtocol.respond = { _ in (503, Data()) }
        await assert(throws: .badResponse(503))
    }

    func testRejectsGarbage() async {
        StubURLProtocol.respond = { _ in (200, Data("<html>nope</html>".utf8)) }
        await assert(throws: .malformedPayload)
    }

    func testRejectsEmptyForecastList() async {
        StubURLProtocol.respond = { _ in (200, Data(#"{"forecasts":[]}"#.utf8)) }
        await assert(throws: .emptyPayload)
    }

    func testTrimsToTheDisplayWindow() async throws {
        // Whole second: the feed's timestamps have no sub-second part, so an
        // arbitrary `now` would put every offset a fraction below its minute.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())
        StubURLProtocol.respond = { [self] _ in
            (200, payload(offsetsInMinutes: [-180, -60, -10, 0, 60, 119, 200, 300], from: now))
        }

        let forecast = try await service.fetchForecast(for: .fallback, now: now)
        let offsets = forecast.readings.map { Int($0.timestamp.timeIntervalSince(now) / 60) }
        XCTAssertEqual(offsets, [-10, 0, 60, 119], "history beyond 30 min and anything past 2 h is dropped")
    }

    func testSendsCoordinatesRoundedToTwoDecimals() async throws {
        let now = Date()
        var seen: URL?
        StubURLProtocol.respond = { [self] request in
            seen = request.url
            return (200, payload(offsetsInMinutes: [0], from: now))
        }

        let precise = WeatherLocation(name: "Somewhere", latitude: 52.376543, longitude: 4.901234, source: .custom)
        _ = try await service.fetchForecast(for: precise, now: now)

        let query = try XCTUnwrap(seen?.query)
        XCTAssertTrue(query.contains("lat=52.38"), query)
        XCTAssertTrue(query.contains("lon=4.90"), query)
    }

    private func assert(throws expected: RainServiceError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await service.fetchForecast(for: .fallback, now: Date())
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as RainServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
