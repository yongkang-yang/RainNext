// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

final class WeatherConditionTests: XCTestCase {
    /// Every code the CDN actually serves, read off the published icons.
    private let published: [String: WeatherCondition] = [
        "a": .clear,
        "b": .partlyCloudy, "j": .partlyCloudy, "r": .partlyCloudy,
        "c": .cloudy, "p": .cloudy,
        "d": .fog, "n": .fog, "o": .fog,
        "f": .drizzle, "m": .drizzle,
        "h": .rain, "k": .rain, "q": .rain,
        "l": .heavyRain,
        "g": .thunder, "s": .thunder,
        "i": .snow, "t": .snow, "u": .snow, "v": .snow,
        "w": .sleet,
    ]

    func testEveryPublishedCodeMaps() {
        XCTAssertEqual(published.count, 22, "the icon set has 22 conditions")
        for (code, expected) in published {
            XCTAssertEqual(WeatherCondition(iconCode: code), expected, "day code \(code)")
            XCTAssertEqual(WeatherCondition(iconCode: code + code), expected, "night code \(code + code)")
        }
    }

    func testDoubledCodesAreNight() {
        XCTAssertFalse(WeatherCondition.isNight(iconCode: "a"))
        XCTAssertTrue(WeatherCondition.isNight(iconCode: "aa"))
        XCTAssertTrue(WeatherCondition.isNight(iconCode: "CC"))
    }

    func testNightChangesOnlyTheSymbolsThatHaveANightForm() {
        XCTAssertEqual(WeatherCondition.clear.symbolName(isNight: false), "sun.max")
        XCTAssertEqual(WeatherCondition.clear.symbolName(isNight: true), "moon.stars")
        // Snow looks the same after dark, in Buienradar's set and in ours.
        XCTAssertEqual(WeatherCondition.snow.symbolName(isNight: false),
                       WeatherCondition.snow.symbolName(isNight: true))
    }

    func testUnknownCodeDoesNotPretend() {
        XCTAssertEqual(WeatherCondition(iconCode: "zz"), .unknown)
        XCTAssertEqual(WeatherCondition(iconCode: ""), .unknown)
    }
}

final class BuienradarFeedParserTests: XCTestCase {
    /// Shaped after a real payload, trimmed to the fields that are used.
    private let payload = Data("""
    {"actual":{"sunrise":"2026-09-21T07:21:00","sunset":"2026-09-21T19:39:00",
     "stationmeasurements":[
      {"stationname":"Meetstation Arnhem","regio":"Arnhem","lat":52.07,"lon":5.88,
       "timestamp":"2026-09-22T00:30:00",
       "weatherdescription":"Vrijwel onbewolkt (zonnig/helder)",
       "iconurl":"https://cdn.buienradar.nl/resources/images/icons/weather/30x30/aa.png",
       "temperature":9.1,"feeltemperature":9.1,"windspeedBft":0,"winddirection":"N"},
      {"stationname":"Meetstation Rotterdam","regio":"Rotterdam","lat":51.95,"lon":4.45,
       "timestamp":"2026-09-22T00:30:00","weatherdescription":"Zwaar bewolkt",
       "iconurl":"https://cdn.buienradar.nl/resources/images/icons/weather/30x30/cc.png",
       "temperature":11.4,"feeltemperature":10.8,"windspeedBft":3,"winddirection":"ZW"},
      {"stationname":"Broken station","regio":"Nowhere","lat":52.0,"lon":5.0,
       "timestamp":"2026-09-22T00:30:00","weatherdescription":null,"iconurl":null,
       "temperature":null,"feeltemperature":null,"windspeedBft":null,"winddirection":null}
     ]}}
    """.utf8)

    func testParsesStationsAndDropsOnesWithoutACondition() throws {
        let stations = try BuienradarFeedParser.parse(payload)
        // The station with no icon cannot answer the question this feed is for.
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations[0].condition, .clear)
        XCTAssertTrue(stations[0].isNight)
        XCTAssertEqual(stations[1].condition, .cloudy)
        XCTAssertEqual(stations[1].windBft, 3)
        XCTAssertEqual(stations[1].temperature, 11.4)
    }

    func testPicksTheNearestStation() throws {
        let stations = try BuienradarFeedParser.parse(payload)
        // Delft is far closer to Rotterdam than to Arnhem.
        let nearest = try XCTUnwrap(StationObservation.nearest(to: 52.01, 4.36, from: stations))
        XCTAssertEqual(nearest.region, "Rotterdam")

        let arnhem = try XCTUnwrap(StationObservation.nearest(to: 52.0, 5.9, from: stations))
        XCTAssertEqual(arnhem.region, "Arnhem")
    }

    func testExtractsIconCodeFromUrl() {
        XCTAssertEqual(
            BuienradarFeedParser.iconCode(from: "https://cdn.buienradar.nl/…/30x30/bb.png"), "bb"
        )
        XCTAssertNil(BuienradarFeedParser.iconCode(from: nil))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try BuienradarFeedParser.parse(Data("nope".utf8)))
    }
}

final class MenuBarConditionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func observation(_ condition: WeatherCondition, night: Bool = false) -> StationObservation {
        StationObservation(
            stationName: "Test", region: "Test", latitude: 52, longitude: 5,
            timestamp: start, condition: condition, isNight: night,
            summary: "", temperature: 9, feelsLike: 9, windBft: 2, windDirection: "N"
        )
    }

    private func episode(in minutes: Double, mmh: Double) -> RainEpisode {
        let begin = start.addingTimeInterval(minutes * 60)
        return RainEpisode(
            start: begin, end: begin.addingTimeInterval(900),
            readings: [RainReading(timestamp: begin, millimetersPerHour: mmh)]
        )
    }

    func testDryShowsTheActualSky() {
        let state = MenuBarState.make(from: .dry(next: nil), observation: observation(.snow), at: start)
        XCTAssertEqual(state.symbolName, "cloud.snow", "a sun while it snows is the bug being fixed")
        XCTAssertNil(state.text)
    }

    func testNightSkyUsesTheNightSymbol() {
        let state = MenuBarState.make(from: .dry(next: nil), observation: observation(.clear, night: true), at: start)
        XCTAssertEqual(state.symbolName, "moon.stars")
    }

    func testRainNowcastOutranksTheStation() {
        // The station says clear; rain is falling. Rain is what this app is for.
        let raining = RainStatus.raining(episode: episode(in: 0, mmh: 1.1), intensity: 1.1)
        let state = MenuBarState.make(from: raining, observation: observation(.clear), at: start)
        XCTAssertEqual(state.text, "1.1")
        XCTAssertNotEqual(state.symbolName, "sun.max")
    }

    func testCountdownOutranksTheStation() {
        let state = MenuBarState.make(
            from: .dry(next: episode(in: 20, mmh: 1.1)), observation: observation(.clear), at: start
        )
        XCTAssertEqual(state.text, "20m")
    }

    func testStationCarriesTheGapWhenTheNowcastIsMissing() {
        let state = MenuBarState.make(from: .unavailable, observation: observation(.fog), at: start)
        XCTAssertEqual(state.symbolName, "cloud.fog")
    }

    func testFallsBackToSunWithNoObservation() {
        XCTAssertEqual(MenuBarState.make(from: .dry(next: nil), at: start).symbolName, "sun.max")
    }
}
