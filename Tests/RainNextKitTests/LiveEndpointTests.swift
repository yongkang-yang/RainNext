// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

/// Hits the real Buienradar feed. Skipped unless `RAINNEXT_LIVE=1`, so the
/// normal suite stays offline and deterministic.
///
///     RAINNEXT_LIVE=1 swift test --filter LiveEndpointTests
final class LiveEndpointTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RAINNEXT_LIVE"] == "1")
    }

    func testFetchesAndDecodesRealPayload() async throws {
        let now = Date()
        let forecast = try await BuienradarRainService(logger: nil).fetchForecast(for: .fallback, now: now)

        XCTAssertFalse(forecast.readings.isEmpty)
        XCTAssertTrue(forecast.readings.allSatisfy { $0.rawValue != nil }, "raw values feed threshold calibration")

        // The window must land around now, not in 1970 or on the wrong day.
        let start = try XCTUnwrap(forecast.start)
        let end = try XCTUnwrap(forecast.end)
        XCTAssertLessThanOrEqual(start, now)
        XCTAssertGreaterThan(end, now)
        XCTAssertLessThanOrEqual(end.timeIntervalSince(now), ForecastWindow.horizon + 600)

        // The long spans ride a second product off the same host. An unknown
        // product name comes back as this same nowcast, at 200, so the live
        // check is that what arrives is actually hourly and actually ahead.
        let hourly = try await BuienradarRainService(logger: nil).fetchHourly(for: .fallback, now: now)
        XCTAssertTrue(HourlyRainForecast.isHourly(hourly.readings), "the hourly product answered with five-minute data")
        XCTAssertGreaterThanOrEqual(hourly.readings(within: .twelveHours, at: now).count, 11)
        let hourlyEnd = try XCTUnwrap(hourly.end(within: .twoDays, at: now))
        XCTAssertGreaterThan(hourlyEnd.timeIntervalSince(now), 24 * 3600, "48h span needs more than a day of data")

        let sky = try await BuienradarObservationService().fetchObservation(near: .fallback)
        XCTAssertNotEqual(sky.condition, .unknown, "a live icon code the mapping does not cover")
        XCTAssertLessThan(abs(sky.timestamp.timeIntervalSince(now)), 3 * 3600,
                          "station observations should be recent")
        print("live sky: \(sky.stationName), \(sky.condition.label), symbol \(sky.symbolName), "
              + "night=\(sky.isNight), summary=\(sky.summary)")

        print("""
        live hourly: \(hourly.readings.count) hours, \
        through \(RainPhrasing.clock(hourlyEnd, relativeTo: now)), \
        12h "\(hourly.summary(within: .twelveHours, at: now) ?? "-")", \
        48h "\(hourly.summary(within: .twoDays, at: now) ?? "-")"
        """)

        print("""
        live: \(forecast.readings.count) readings, \
        \(forecast.readings.filter { $0.timestamp < now }.count) past, \
        \(forecast.episodes.count) episodes, \
        status "\(forecast.status(at: now).headline(at: now))", \
        menu bar \(MenuBarState.make(from: forecast.status(at: now), at: now))
        """)
    }
}
