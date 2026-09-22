// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

final class HourlyRainForecastTests: XCTestCase {
    /// Friday 15 January 2027, 12:00 UTC — fixed so weekday names are stable.
    private let noon = Date(timeIntervalSince1970: 1_800_014_400)

    /// Hourly rates, the first covering the hour that opens at `noon`.
    private func hourly(_ rates: [Double], from start: Date? = nil) -> HourlyRainForecast {
        let first = start ?? noon
        let readings = rates.enumerated().map { index, rate in
            RainReading(timestamp: first.addingTimeInterval(Double(index) * 3600), millimetersPerHour: rate)
        }
        return HourlyRainForecast(location: .fallback, readings: readings, fetchedAt: first)
    }

    // MARK: - Telling the feeds apart

    func testRecognisesHourlySpacing() {
        XCTAssertTrue(HourlyRainForecast.isHourly(hourly(Array(repeating: 0, count: 12)).readings))
    }

    /// The host answers an unknown product name with the two-hour nowcast at
    /// 200, so without this the app would draw five-minute radar as two days.
    func testRejectsTheNowcastArrivingInsteadOfHourlyData() {
        let fiveMinute = (0..<24).map {
            RainReading(timestamp: noon.addingTimeInterval(Double($0) * 300), millimetersPerHour: 0)
        }
        XCTAssertFalse(HourlyRainForecast.isHourly(fiveMinute))
    }

    func testRejectsAPayloadWithNothingToMeasure() {
        XCTAssertFalse(HourlyRainForecast.isHourly([]))
        XCTAssertFalse(HourlyRainForecast.isHourly([RainReading(timestamp: noon, millimetersPerHour: 0)]))
    }

    // MARK: - Windowing

    func testTwelveHoursTakesTwelveHours() {
        let forecast = hourly(Array(repeating: 0, count: 48))
        XCTAssertEqual(forecast.readings(within: .twelveHours, at: noon).count, 12)
        XCTAssertEqual(forecast.readings(within: .twoDays, at: noon).count, 48)
    }

    /// The feed opens on the next full hour, so at 12:20 the 12:00 sample is
    /// the hour in progress and still belongs on the chart.
    func testKeepsTheHourAlreadyUnderWay() {
        let forecast = hourly(Array(repeating: 0, count: 24))
        let window = forecast.readings(within: .twelveHours, at: noon.addingTimeInterval(20 * 60))
        XCTAssertEqual(window.first?.timestamp, noon)
    }

    func testDropsHoursThatHaveRunOut() {
        let forecast = hourly(Array(repeating: 0, count: 24))
        // 15:20: the 14:00 hour is over, the 15:00 one is the one being lived in.
        let window = forecast.readings(within: .twelveHours, at: noon.addingTimeInterval(3 * 3600 + 20 * 60))
        XCTAssertEqual(window.first?.timestamp, noon.addingTimeInterval(3 * 3600))
    }

    // MARK: - Summary

    func testSaysDryThroughTheEndOfTheSpan() throws {
        let forecast = hourly(Array(repeating: 0, count: 48))
        let summary = try XCTUnwrap(forecast.summary(within: .twelveHours, at: noon))
        XCTAssertTrue(summary.hasPrefix("Dry through "), summary)
    }

    func testNamesTheFirstWetHourAndThePeak() throws {
        // Dry until the fourth hour, then a shower peaking at 1.4 mm/h.
        let forecast = hourly([0, 0, 0, 0.2, 1.4, 0.3] + Array(repeating: 0, count: 18))
        let summary = try XCTUnwrap(forecast.summary(within: .twelveHours, at: noon))
        XCTAssertTrue(summary.contains("1.4 mm/h"), summary)
        XCTAssertTrue(summary.hasPrefix("Rain around "), summary)
    }

    /// A shower past the edge of the span is not this span's problem.
    func testIgnoresRainBeyondTheSpan() throws {
        let forecast = hourly(Array(repeating: 0, count: 20) + [2.0])
        let summary = try XCTUnwrap(forecast.summary(within: .twelveHours, at: noon))
        XCTAssertTrue(summary.hasPrefix("Dry through "), summary)
        XCTAssertTrue(forecast.summary(within: .twoDays, at: noon)?.hasPrefix("Rain around ") == true)
    }

    func testSaysNothingWithoutData() {
        XCTAssertNil(hourly([]).summary(within: .twelveHours, at: noon))
    }

    // MARK: - Day-aware clock

    func testClockStaysBareWithinTheDay() {
        let later = noon.addingTimeInterval(3 * 3600)
        XCTAssertEqual(RainPhrasing.clock(later, relativeTo: noon), RainPhrasing.clock(later))
    }

    /// "18:00" two days out looks like today's 18:00, which is the whole
    /// reason the long spans need the day spelled out.
    /// The hour after 23:00 ends at midnight, and the clock's own name for
    /// that is "12:00 AM tomorrow" — right, and read as a bug.
    func testMidnightIsNamedAsTheEndOfADay() {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: noon.addingTimeInterval(24 * 3600))
        XCTAssertEqual(RainPhrasing.boundary(midnight, relativeTo: noon), "midnight")
        XCTAssertEqual(
            RainPhrasing.boundary(midnight.addingTimeInterval(24 * 3600), relativeTo: noon),
            "tomorrow midnight"
        )
    }

    func testBoundaryLeavesOrdinaryTimesAlone() {
        let six = noon.addingTimeInterval(6 * 3600)
        XCTAssertEqual(RainPhrasing.boundary(six, relativeTo: noon), RainPhrasing.clock(six))
    }

    func testClockNamesAnotherDay() {
        let tomorrow = noon.addingTimeInterval(24 * 3600)
        let overmorrow = noon.addingTimeInterval(48 * 3600)
        XCTAssertTrue(RainPhrasing.clock(tomorrow, relativeTo: noon).hasPrefix("tomorrow "))
        XCTAssertNotEqual(RainPhrasing.clock(overmorrow, relativeTo: noon), RainPhrasing.clock(overmorrow))
    }
}
