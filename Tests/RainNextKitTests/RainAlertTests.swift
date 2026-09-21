// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

final class RainAlertPlannerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Rates in mm/h at five-minute spacing, starting at `start`.
    private func forecast(_ rates: [Double]) -> RainForecast {
        let readings = rates.enumerated().map { index, rate in
            RainReading(timestamp: start.addingTimeInterval(Double(index) * 300), millimetersPerHour: rate)
        }
        return RainForecast(location: .fallback, readings: readings, fetchedAt: start)
    }

    /// Dry for `dryMinutes`, then a solid stretch of rain.
    private func rainStarting(inMinutes dryMinutes: Int, rate: Double = 1.1) -> RainForecast {
        let drySlots = dryMinutes / 5
        return forecast(Array(repeating: 0, count: drySlots) + Array(repeating: rate, count: 6))
    }

    func testAnnouncesRainInsideTheHorizon() throws {
        let alert = try XCTUnwrap(RainAlertPlanner.alert(for: rainStarting(inMinutes: 15), at: start, ledger: .init()))
        XCTAssertEqual(alert.title, "Rain in 15 min")
        XCTAssertEqual(alert.episodeStart, start.addingTimeInterval(15 * 60))
    }

    func testSaysNothingAboutRainStillFarOff() {
        // 45 minutes out: the nowcast will have changed its mind twice by then.
        XCTAssertNil(RainAlertPlanner.alert(for: rainStarting(inMinutes: 45), at: start, ledger: .init()))
    }

    func testSaysNothingWhileAlreadyRaining() {
        let raining = forecast([1.1, 1.1, 1.1, 0, 0, 1.1, 1.1])
        XCTAssertNil(RainAlertPlanner.alert(for: raining, at: start.addingTimeInterval(60), ledger: .init()))
    }

    func testIgnoresDrizzleTheMenuBarWouldAlsoIgnore() {
        // Same floor as the countdown: never interrupt for something the app
        // would not even display.
        XCTAssertNil(RainAlertPlanner.alert(for: rainStarting(inMinutes: 15, rate: 0.25), at: start, ledger: .init()))
    }

    func testDoesNotRepeatTheSameShowerWhenTheForecastDrifts() throws {
        let first = try XCTUnwrap(RainAlertPlanner.alert(for: rainStarting(inMinutes: 20), at: start, ledger: .init()))
        var ledger = RainAlertPlanner.Ledger()
        ledger.record(first, at: start)

        // Five minutes later the nowcast has nudged the start earlier. Same
        // shower, and the ledger must recognise it despite the moved start.
        let later = start.addingTimeInterval(300)
        let drifted = RainForecast(
            location: .fallback,
            readings: (0..<12).map { index in
                RainReading(
                    timestamp: later.addingTimeInterval(Double(index) * 300),
                    millimetersPerHour: index >= 2 ? 1.1 : 0
                )
            },
            fetchedAt: later
        )
        XCTAssertNil(RainAlertPlanner.alert(for: drifted, at: later, ledger: ledger))
    }

    func testAnnouncesAGenuinelyNewShowerAfterTheOldOnePasses() throws {
        var ledger = RainAlertPlanner.Ledger()
        ledger.record(
            RainAlert(
                title: "old", body: "old",
                episodeStart: start.addingTimeInterval(-3600),
                episodeEnd: start.addingTimeInterval(-1800)
            ),
            at: start.addingTimeInterval(-3600)
        )

        let alert = try XCTUnwrap(RainAlertPlanner.alert(for: rainStarting(inMinutes: 15), at: start, ledger: ledger))
        XCTAssertEqual(alert.episodeStart, start.addingTimeInterval(900))
    }

    func testHoldsBackWhenItSpokeTooRecently() {
        var ledger = RainAlertPlanner.Ledger()
        ledger.lastNotifiedAt = start.addingTimeInterval(-60)
        XCTAssertNil(RainAlertPlanner.alert(for: rainStarting(inMinutes: 15), at: start, ledger: ledger))
    }

    func testBodyCarriesDurationAndEnd() throws {
        let alert = try XCTUnwrap(RainAlertPlanner.alert(for: rainStarting(inMinutes: 15), at: start, ledger: .init()))
        XCTAssertTrue(alert.body.hasPrefix("About 30 min, until "), alert.body)
    }

    func testHeavyRainSaysSoInTheTitle() throws {
        let alert = try XCTUnwrap(RainAlertPlanner.alert(for: rainStarting(inMinutes: 10, rate: 4), at: start, ledger: .init()))
        XCTAssertEqual(alert.title, "Heavy rain in 10 min")
    }
}
