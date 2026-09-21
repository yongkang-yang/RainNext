// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

final class RainReadingTests: XCTestCase {
    func testRateComesStraightFromTheFeed() {
        // The feed's own number is kept as-is; nothing is recomputed from the
        // raw value, whose scale belongs to the provider.
        let reading = RainReading(timestamp: .now, millimetersPerHour: 0.55, rawValue: 11)
        XCTAssertEqual(reading.millimetersPerHour, 0.55)
        XCTAssertEqual(reading.rawValue, 11)
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
       {"datetime":"2026-09-21T19:25:00","utcdatetime":"2026-09-21T17:25:00","precipitation":0.55,"precipation":0.55,"original":11,"value":11},
       {"datetime":"2026-09-21T19:35:00","utcdatetime":"2026-09-21T17:35:00","precipitation":1.2,"precipation":1.2,"original":24,"value":24}
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
        XCTAssertEqual(readings[1].millimetersPerHour, 0.55)
        XCTAssertEqual(readings[1].rawValue, 11)
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

    /// Rates in mm/h, one sample per five minutes.
    private func readings(_ rates: [Double]) -> [RainReading] {
        rates.enumerated().map { index, rate in
            RainReading(timestamp: start.addingTimeInterval(Double(index) * 300), millimetersPerHour: rate)
        }
    }

    func testBuildsEpisodeFromConsecutiveWetReadings() throws {
        let episodes = RainEpisode.episodes(from: readings([0, 0, 0.25, 1.1, 2.2, 0, 0]))

        XCTAssertEqual(episodes.count, 1)
        let episode = try XCTUnwrap(episodes.first)
        XCTAssertEqual(episode.start, start.addingTimeInterval(600))
        XCTAssertEqual(episode.duration, 900)
        XCTAssertEqual(episode.peak, .moderate, "2.2 mm/h sits under the 2.5 heavy line")
    }

    func testBridgesSingleDrySample() {
        let episodes = RainEpisode.episodes(from: readings([0.5, 0.5, 0, 0.5, 0.5]))
        XCTAssertEqual(episodes.count, 1, "One dropped sample mid-shower is still one shower")
    }

    func testSplitsOnLongDryGap() {
        let episodes = RainEpisode.episodes(from: readings([0.5, 0.5, 0, 0, 0, 0, 0.5, 0.5]))
        XCTAssertEqual(episodes.count, 2)
    }

    func testDiscardsSingleSampleBlip() {
        // Five minutes of rain bracketed by dry is radar clutter more often than weather.
        XCTAssertTrue(RainEpisode.episodes(from: readings([0, 0.5, 0, 0])).isEmpty)
    }

    func testNoEpisodesWhenDry() {
        XCTAssertTrue(RainEpisode.episodes(from: readings([0, 0, 0])).isEmpty)
    }

    func testSlotEndFollowsActualSpacing() throws {
        // 17:30 missing: the wet slot at +300 runs until the next real sample.
        let uneven = [
            RainReading(timestamp: start, millimetersPerHour: 0.5),
            RainReading(timestamp: start.addingTimeInterval(300), millimetersPerHour: 0.5),
            RainReading(timestamp: start.addingTimeInterval(900), millimetersPerHour: 0),
        ]
        let episode = try XCTUnwrap(RainEpisode.episodes(from: uneven).first)
        XCTAssertEqual(episode.end, start.addingTimeInterval(900))
    }

    func testCapsUnknownStretchAfterALongOutage() throws {
        let outage = [
            RainReading(timestamp: start, millimetersPerHour: 0.5),
            RainReading(timestamp: start.addingTimeInterval(300), millimetersPerHour: 0.5),
            RainReading(timestamp: start.addingTimeInterval(3600), millimetersPerHour: 0),
        ]
        let episode = try XCTUnwrap(RainEpisode.episodes(from: outage).first)
        XCTAssertEqual(episode.end, start.addingTimeInterval(900), "an hour-long hole is not an hour of rain")
    }

    func testDrizzleIsAnEpisodeButNotAnnounceable() throws {
        let episode = try XCTUnwrap(RainEpisode.episodes(from: readings([0.25, 0.25, 0.25, 0])).first)
        XCTAssertGreaterThan(episode.peakIntensity, RainThresholds.episodeFloor)
        XCTAssertFalse(episode.isAnnounceable, "0.25 mm/h belongs on the graph, not in the menu bar")
    }
}

final class RainStatusTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func forecast(_ rates: [Double]) -> RainForecast {
        let readings = rates.enumerated().map { index, rate in
            RainReading(timestamp: start.addingTimeInterval(Double(index) * 300), millimetersPerHour: rate)
        }
        return RainForecast(location: .fallback, readings: readings, fetchedAt: start)
    }

    func testDryNowWithUpcomingRain() {
        let status = forecast([0, 0, 0, 1.1, 1.1]).status(at: start)
        guard case .dry(let next) = status else { return XCTFail("expected dry, got \(status)") }
        XCTAssertEqual(next?.start, start.addingTimeInterval(900))
        XCTAssertEqual(status.headline(at: start), "Rain in 15 min")
    }

    func testRainingNow() {
        let status = forecast([2.2, 2.2, 0]).status(at: start.addingTimeInterval(60))
        guard case .raining(let episode, let intensity) = status else { return XCTFail("expected rain, got \(status)") }
        XCTAssertEqual(episode.duration, 600)
        XCTAssertGreaterThan(intensity, 1)
    }

    func testDryWholeWindow() {
        XCTAssertEqual(forecast([0.0, 0, 0]).headlineNow(start), "Dry for the next 2 hours")
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

    private func episode(in minutes: Double, mmh: Double, lasting: Double = 15) -> RainEpisode {
        let begin = start.addingTimeInterval(minutes * 60)
        return RainEpisode(
            start: begin,
            end: begin.addingTimeInterval(lasting * 60),
            readings: [RainReading(timestamp: begin, millimetersPerHour: mmh)]
        )
    }

    func testDryShowsNoText() {
        let state = MenuBarState.make(from: .dry(next: nil), at: start)
        XCTAssertNil(state.text)
        XCTAssertEqual(state.symbolName, "sun.max")
    }

    func testCountdownForUpcomingRain() {
        let state = MenuBarState.make(from: .dry(next: episode(in: 27, mmh: 1.1)), at: start)
        XCTAssertEqual(state.text, "27m")
    }

    func testDrizzleGetsNoCountdown() {
        // Real rain, but not worth a promise the sky may not keep.
        let state = MenuBarState.make(from: .dry(next: episode(in: 27, mmh: 0.25)), at: start)
        XCTAssertNil(state.text)
        XCTAssertEqual(state.symbolName, "sun.max")
    }

    func testDistantRainIsNotCountedDown() {
        let minutes = MenuBarState.countdownHorizon / 60 + 10
        XCTAssertNil(MenuBarState.make(from: .dry(next: episode(in: minutes, mmh: 1.1)), at: start).text)
    }

    func testRateWhenRaining() {
        let now = episode(in: 0, mmh: 1.1)
        XCTAssertEqual(MenuBarState.make(from: .raining(episode: now, intensity: 0.84), at: start).text, "0.8")
    }

    func testCurrentDrizzleIsStillShown() {
        // The announce floor gates forecasts, not what is happening right now.
        let now = episode(in: 0, mmh: 0.25)
        XCTAssertEqual(MenuBarState.make(from: .raining(episode: now, intensity: 0.25), at: start).text, "0.2")
    }
}
