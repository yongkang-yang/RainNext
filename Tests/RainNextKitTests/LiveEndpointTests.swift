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

        print("""
        live: \(forecast.readings.count) readings, \
        \(forecast.readings.filter { $0.timestamp < now }.count) past, \
        \(forecast.episodes.count) episodes, \
        status "\(forecast.status(at: now).headline(at: now))", \
        menu bar \(MenuBarState.make(from: forecast.status(at: now), at: now))
        """)
    }
}
