import XCTest
@testable import RainNextKit

final class RainReadingTests: XCTestCase {
    func testRawValueConversion() {
        XCTAssertEqual(RainReading(timestamp: .now, rawValue: 0).millimetersPerHour, 0)
        // Documented anchor: 109 maps to 1 mm/h.
        XCTAssertEqual(RainReading(timestamp: .now, rawValue: 109).millimetersPerHour, 1, accuracy: 0.0001)
        XCTAssertEqual(RainReading(timestamp: .now, rawValue: 77).millimetersPerHour, 0.1, accuracy: 0.01)
    }

    func testDryBelowThreshold() {
        XCTAssertFalse(RainReading(timestamp: .now, rawValue: 60).isRaining)
        XCTAssertTrue(RainReading(timestamp: .now, rawValue: 90).isRaining)
    }
}

final class BuienradarParserTests: XCTestCase {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    private func reference(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = amsterdam
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)!
    }

    func testParsesValuesAndOrder() {
        let payload = "000|19:20\n077|19:25\n120|19:30\n"
        let readings = BuienradarParser.parse(payload, reference: reference("2026-09-21T19:18:00+02:00"))

        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings.map(\.rawValue), [0, 77, 120])
        XCTAssertEqual(readings[1].timestamp.timeIntervalSince(readings[0].timestamp), 300)
    }

    func testRollsOverMidnight() {
        let payload = "000|23:55\n100|00:00\n100|00:05\n"
        let readings = BuienradarParser.parse(payload, reference: reference("2026-09-21T23:53:00+02:00"))

        XCTAssertEqual(readings.count, 3)
        // The 00:00 sample must land on the *next* day, not 24 hours earlier.
        XCTAssertEqual(readings[1].timestamp.timeIntervalSince(readings[0].timestamp), 300)
        XCTAssertEqual(readings[2].timestamp.timeIntervalSince(readings[1].timestamp), 300)
    }

    func testSkipsMalformedLines() {
        let payload = "000|19:20\ngarbage\n|\n077|19:25\n"
        XCTAssertEqual(BuienradarParser.parse(payload, reference: reference("2026-09-21T19:18:00+02:00")).count, 2)
    }
}

final class RainEpisodeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func readings(_ values: [Int]) -> [RainReading] {
        values.enumerated().map { index, value in
            RainReading(timestamp: start.addingTimeInterval(Double(index) * 300), rawValue: value)
        }
    }

    func testBuildsEpisodeFromConsecutiveWetReadings() {
        let episodes = RainEpisode.episodes(from: readings([0, 0, 90, 110, 120, 0, 0]))

        XCTAssertEqual(episodes.count, 1)
        let episode = try! XCTUnwrap(episodes.first)
        XCTAssertEqual(episode.start, start.addingTimeInterval(600))
        XCTAssertEqual(episode.duration, 900)
        XCTAssertEqual(episode.peak, .heavy, "raw 120 is ~2.2 mm/h")
    }

    func testBridgesSingleDrySample() {
        let episodes = RainEpisode.episodes(from: readings([100, 100, 0, 100, 100]))
        XCTAssertEqual(episodes.count, 1, "One dropped sample mid-shower is still one shower")
    }

    func testSplitsOnLongDryGap() {
        let episodes = RainEpisode.episodes(from: readings([100, 0, 0, 0, 0, 100]))
        XCTAssertEqual(episodes.count, 2)
    }

    func testNoEpisodesWhenDry() {
        XCTAssertTrue(RainEpisode.episodes(from: readings([0, 0, 0])).isEmpty)
    }
}

final class RainStatusTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func forecast(_ values: [Int]) -> RainForecast {
        let readings = values.enumerated().map { index, value in
            RainReading(timestamp: start.addingTimeInterval(Double(index) * 300), rawValue: value)
        }
        return RainForecast(location: .fallback, readings: readings, fetchedAt: start)
    }

    func testDryNowWithUpcomingRain() {
        let status = forecast([0, 0, 0, 110, 110]).status(at: start)
        guard case .dry(let next) = status else { return XCTFail("expected dry, got \(status)") }
        XCTAssertEqual(next?.start, start.addingTimeInterval(900))
        XCTAssertEqual(status.headline(at: start), "Rain in 15 min")
    }

    func testRainingNow() {
        let status = forecast([120, 120, 0]).status(at: start.addingTimeInterval(60))
        guard case .raining(let episode, let intensity) = status else { return XCTFail("expected rain, got \(status)") }
        XCTAssertEqual(episode.duration, 600)
        XCTAssertGreaterThan(intensity, 1)
    }

    func testDryWholeWindow() {
        let status = forecast([0, 0, 0]).status(at: start)
        XCTAssertEqual(status.headline(at: start), "Dry for the next 2 hours")
    }

    func testUnavailableWithoutReadings() {
        XCTAssertEqual(RainForecast(location: .fallback, readings: [], fetchedAt: start).status(at: start), .unavailable)
    }
}

final class MenuBarStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testDryShowsNoText() {
        let state = MenuBarState.make(from: .dry(next: nil), at: start)
        XCTAssertNil(state.text)
        XCTAssertEqual(state.symbolName, "sun.max")
    }

    func testCountdownForUpcomingRain() {
        let episode = RainEpisode(
            start: start.addingTimeInterval(27 * 60),
            end: start.addingTimeInterval(45 * 60),
            readings: [RainReading(timestamp: start.addingTimeInterval(27 * 60), rawValue: 110)]
        )
        XCTAssertEqual(MenuBarState.make(from: .dry(next: episode), at: start).text, "27m")
    }

    func testDistantRainIsNotCountedDown() {
        let far = start.addingTimeInterval(MenuBarState.countdownHorizon + 600)
        let episode = RainEpisode(start: far, end: far.addingTimeInterval(300), readings: [])
        XCTAssertNil(MenuBarState.make(from: .dry(next: episode), at: start).text)
    }

    func testRateWhenRaining() {
        let episode = RainEpisode(start: start, end: start.addingTimeInterval(600), readings: [])
        XCTAssertEqual(MenuBarState.make(from: .raining(episode: episode, intensity: 0.84), at: start).text, "0.8")
    }
}
