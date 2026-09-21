// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

final class RainReadingTests: XCTestCase {
    func testRawValueConversion() {
        // Kept because the feed still carries the raw radar number, and
        // calibrating the thresholds (BD-108) needs to read it.
        XCTAssertEqual(RainReading.millimetersPerHour(fromRawValue: 0), 0)
        XCTAssertEqual(RainReading.millimetersPerHour(fromRawValue: 109), 1, accuracy: 0.0001)
        XCTAssertEqual(RainReading.millimetersPerHour(fromRawValue: 77), 0.1, accuracy: 0.01)
    }

    func testRateComesStraightFromTheFeed() {
        let reading = RainReading(timestamp: .now, millimetersPerHour: 0.53, rawValue: 100)
        XCTAssertEqual(reading.millimetersPerHour, 0.53)
        XCTAssertEqual(reading.rawValue, 100)
    }

    func testDryBelowFloor() {
        XCTAssertFalse(RainReading(timestamp: .now, millimetersPerHour: 0.05).isRaining)
        XCTAssertTrue(RainReading(timestamp: .now, millimetersPerHour: 0.2).isRaining)
    }
}

final class BuienradarForecastParserTests: XCTestCase {
    /// Shaped after a real response, including the dropped 17:30 slot.
    private let payload = Data("""
    {"color":"#5A9BD3","lat":52.09,"lon":5.11,
     "borders":[{"title":"licht","lower":0,"upper":40}],
     "forecasts":[
       {"datetime":"2026-09-21T19:20:00","utcdatetime":"2026-09-21T17:20:00","precipitation":0.0,"precipation":0.0,"original":0,"value":0},
       {"datetime":"2026-09-21T19:25:00","utcdatetime":"2026-09-21T17:25:00","precipitation":0.53,"precipation":0.53,"original":100,"value":10},
       {"datetime":"2026-09-21T19:35:00","utcdatetime":"2026-09-21T17:35:00","precipitation":1.2,"precipation":1.2,"original":112,"value":22}
     ]}
    """.utf8)

    func testParsesTimestampsAsUTC() throws {
        let readings = try BuienradarForecastParser.parse(payload)
        XCTAssertEqual(readings.count, 3)

        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 21
        components.hour = 17; components.minute = 20
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        XCTAssertEqual(readings[0].timestamp, calendar.date(from: components))
    }

    func testTakesRateAndRawValueFromTheFeed() throws {
        let readings = try BuienradarForecastParser.parse(payload)
        XCTAssertEqual(readings[1].millimetersPerHour, 0.53)
        XCTAssertEqual(readings[1].rawValue, 100)
    }

    func testPreservesUnevenSpacing() throws {
        let readings = try BuienradarForecastParser.parse(payload)
        // The feed skipped 17:30; nothing may quietly renumber the slots.
        XCTAssertEqual(readings[1].timestamp.timeIntervalSince(readings[0].timestamp), 300)
        XCTAssertEqual(readings[2].timestamp.timeIntervalSince(readings[1].timestamp), 600)
    }

    func testThrowsOnGarbage() {
        XCTAssertThrowsError(try BuienradarForecastParser.parse(Data("not json".utf8)))
    }
}

final class RainEpisodeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func readings(_ values: [Int]) -> [RainReading] {
        values.enumerated().map { index, value in
            RainReading(timestamp: start.addingTimeInterval(Double(index) * 300), rawValue: value)
        }
    }

    func testBuildsEpisodeFromConsecutiveWetReadings() throws {
        let episodes = RainEpisode.episodes(from: readings([0, 0, 90, 110, 120, 0, 0]))

        XCTAssertEqual(episodes.count, 1)
        let episode = try XCTUnwrap(episodes.first)
        XCTAssertEqual(episode.start, start.addingTimeInterval(600))
        XCTAssertEqual(episode.duration, 900)
        XCTAssertEqual(episode.peak, .moderate, "raw 120 is ~2.2 mm/h, under the 2.5 heavy line")
    }

    func testBridgesSingleDrySample() {
        let episodes = RainEpisode.episodes(from: readings([100, 100, 0, 100, 100]))
        XCTAssertEqual(episodes.count, 1, "One dropped sample mid-shower is still one shower")
    }

    func testSplitsOnLongDryGap() {
        let episodes = RainEpisode.episodes(from: readings([100, 100, 0, 0, 0, 0, 100, 100]))
        XCTAssertEqual(episodes.count, 2)
    }

    func testDiscardsSingleSampleBlip() {
        // Five minutes of rain bracketed by dry is radar clutter more often than weather.
        XCTAssertTrue(RainEpisode.episodes(from: readings([0, 100, 0, 0])).isEmpty)
    }

    func testNoEpisodesWhenDry() {
        XCTAssertTrue(RainEpisode.episodes(from: readings([0, 0, 0])).isEmpty)
    }

    func testSlotEndFollowsActualSpacing() throws {
        // 17:30 missing: the wet slot at +300 runs until the next real sample.
        let uneven = [
            RainReading(timestamp: start, rawValue: 100),
            RainReading(timestamp: start.addingTimeInterval(300), rawValue: 100),
            RainReading(timestamp: start.addingTimeInterval(900), rawValue: 0),
        ]
        let episode = try XCTUnwrap(RainEpisode.episodes(from: uneven).first)
        XCTAssertEqual(episode.end, start.addingTimeInterval(900))
    }

    func testCapsUnknownStretchAfterALongOutage() throws {
        let outage = [
            RainReading(timestamp: start, rawValue: 100),
            RainReading(timestamp: start.addingTimeInterval(300), rawValue: 100),
            RainReading(timestamp: start.addingTimeInterval(3600), rawValue: 0),
        ]
        let episode = try XCTUnwrap(RainEpisode.episodes(from: outage).first)
        XCTAssertEqual(episode.end, start.addingTimeInterval(900), "an hour-long hole is not an hour of rain")
    }

    func testDrizzleIsAnEpisodeButNotAnnounceable() throws {
        let episode = try XCTUnwrap(RainEpisode.episodes(from: readings([90, 90, 90, 0])).first)
        XCTAssertGreaterThan(episode.peakIntensity, RainThresholds.episodeFloor)
        XCTAssertFalse(episode.isAnnounceable, "~0.25 mm/h belongs on the graph, not in the menu bar")
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
        XCTAssertEqual(forecast([0, 0, 0]).headlineNow(start), "Dry for the next 2 hours")
    }

    func testUnavailableWithoutReadings() {
        XCTAssertEqual(RainForecast(location: .fallback, readings: [], fetchedAt: start).status(at: start), .unavailable)
    }
}

private extension RainForecast {
    func headlineNow(_ date: Date) -> String { status(at: date).headline(at: date) }
}

final class MenuBarStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func episode(in minutes: Double, rawValue: Int, lasting: Double = 15) -> RainEpisode {
        let begin = start.addingTimeInterval(minutes * 60)
        return RainEpisode(
            start: begin,
            end: begin.addingTimeInterval(lasting * 60),
            readings: [RainReading(timestamp: begin, rawValue: rawValue)]
        )
    }

    func testDryShowsNoText() {
        let state = MenuBarState.make(from: .dry(next: nil), at: start)
        XCTAssertNil(state.text)
        XCTAssertEqual(state.symbolName, "sun.max")
    }

    func testCountdownForUpcomingRain() {
        let state = MenuBarState.make(from: .dry(next: episode(in: 27, rawValue: 110)), at: start)
        XCTAssertEqual(state.text, "27m")
    }

    func testDrizzleGetsNoCountdown() {
        // raw 90 is ~0.25 mm/h: real, but not worth a promise the sky may not keep.
        let state = MenuBarState.make(from: .dry(next: episode(in: 27, rawValue: 90)), at: start)
        XCTAssertNil(state.text)
        XCTAssertEqual(state.symbolName, "sun.max")
    }

    func testDistantRainIsNotCountedDown() {
        let minutes = MenuBarState.countdownHorizon / 60 + 10
        XCTAssertNil(MenuBarState.make(from: .dry(next: episode(in: minutes, rawValue: 110)), at: start).text)
    }

    func testRateWhenRaining() {
        let now = episode(in: 0, rawValue: 110)
        XCTAssertEqual(MenuBarState.make(from: .raining(episode: now, intensity: 0.84), at: start).text, "0.8")
    }

    func testCurrentDrizzleIsStillShown() {
        // The announce floor gates forecasts, not what is happening right now.
        let now = episode(in: 0, rawValue: 90)
        XCTAssertEqual(MenuBarState.make(from: .raining(episode: now, intensity: 0.25), at: start).text, "0.2")
    }
}
