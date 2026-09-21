// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RainNextKit

final class BuienradarCoverageTests: XCTestCase {
    func testCoversTheBenelux() {
        XCTAssertTrue(BuienradarCoverage.contains(latitude: 52.37, longitude: 4.90))  // Amsterdam
        XCTAssertTrue(BuienradarCoverage.contains(latitude: 50.85, longitude: 4.35))  // Brussels
        XCTAssertTrue(BuienradarCoverage.contains(latitude: 49.61, longitude: 6.13))  // Luxembourg
        XCTAssertTrue(BuienradarCoverage.contains(latitude: 53.22, longitude: 6.57))  // Groningen
    }

    func testExcludesPlacesTheFeed404s() {
        XCTAssertFalse(BuienradarCoverage.contains(latitude: 48.86, longitude: 2.35))    // Paris
        XCTAssertFalse(BuienradarCoverage.contains(latitude: 51.51, longitude: -0.13))   // London
        XCTAssertFalse(BuienradarCoverage.contains(latitude: 52.52, longitude: 13.40))   // Berlin
        XCTAssertFalse(BuienradarCoverage.contains(latitude: 40.71, longitude: -74.01))  // New York
    }

    func testBoundsRoundInward() {
        // Measured edges were 49.508 and 54.805; the box must not over-claim.
        XCTAssertFalse(BuienradarCoverage.contains(latitude: 49.50, longitude: 5.0))
        XCTAssertFalse(BuienradarCoverage.contains(latitude: 54.81, longitude: 5.0))
        XCTAssertTrue(BuienradarCoverage.contains(latitude: 49.52, longitude: 5.0))
        XCTAssertTrue(BuienradarCoverage.contains(latitude: 54.79, longitude: 5.0))
    }
}

final class WeatherLocationTests: XCTestCase {
    func testSamePlaceIgnoresTinyCoordinateDifferences() {
        let a = WeatherLocation(name: "Utrecht", latitude: 52.0907, longitude: 5.1214, source: .custom)
        let b = WeatherLocation(name: "Utrecht, Netherlands", latitude: 52.0920, longitude: 5.1180, source: .custom)
        let c = WeatherLocation(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041, source: .custom)

        XCTAssertNotEqual(a.id, b.id, "two searches make two ids")
        XCTAssertTrue(a.isSamePlace(as: b))
        XCTAssertFalse(a.isSamePlace(as: c))
    }
}

final class LocationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "RainNextTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSeedsPresetsOnFirstLaunchOnly() {
        let store = LocationStore(defaults: defaults)
        XCTAssertEqual(store.seedIfNeeded().count, WeatherLocation.presets.count)

        store.favourites = []
        // Deleting everything must stick — seeding is not a repeating default.
        XCTAssertTrue(store.seedIfNeeded().isEmpty)
    }

    func testFavouritesRoundTrip() {
        let store = LocationStore(defaults: defaults)
        let place = WeatherLocation(name: "Delft", latitude: 52.0116, longitude: 4.3571, source: .custom)
        store.favourites = [place]

        let reloaded = LocationStore(defaults: defaults).favourites
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.name, "Delft")
        XCTAssertEqual(reloaded.first?.id, place.id)
    }

    func testFavouritesAreCapped() {
        let store = LocationStore(defaults: defaults)
        store.favourites = (0..<40).map {
            WeatherLocation(name: "Place \($0)", latitude: 52, longitude: 5, source: .custom)
        }
        XCTAssertEqual(store.favourites.count, LocationStore.favouritesLimit)
    }

    func testSelectedRoundTripAndClear() {
        let store = LocationStore(defaults: defaults)
        store.selected = .fallback
        XCTAssertEqual(store.selected?.id, WeatherLocation.fallback.id)

        store.selected = nil
        XCTAssertNil(store.selected)
    }
}

final class PlaceSearchOutcomeTests: XCTestCase {
    private func place(_ name: String, _ latitude: Double, _ longitude: Double) -> WeatherLocation {
        WeatherLocation(name: name, latitude: latitude, longitude: longitude, source: .custom)
    }

    func testCoveredPlacesAreReturnedWithoutAMessage() {
        let outcome = PlaceSearchService.outcome(forFound: [place("Delft", 52.0116, 4.3571)])
        XCTAssertEqual(outcome.results.count, 1)
        XCTAssertNil(outcome.message)
    }

    func testUncoveredPlacesSayWhyRatherThanNothing() {
        // Finding Paris and finding nothing are different answers to the user.
        let outcome = PlaceSearchService.outcome(forFound: [place("Paris", 48.8566, 2.3522)])
        XCTAssertTrue(outcome.results.isEmpty)
        XCTAssertEqual(outcome.message, PlaceSearchService.outsideCoverage)
    }

    func testNothingFoundSaysSo() {
        let outcome = PlaceSearchService.outcome(forFound: [])
        XCTAssertEqual(outcome.message, PlaceSearchService.noResults)
    }

    func testMixedResultsKeepOnlyTheCoveredOnes() {
        let outcome = PlaceSearchService.outcome(forFound: [
            place("Paris", 48.8566, 2.3522),
            place("Utrecht", 52.0907, 5.1214),
        ])
        XCTAssertEqual(outcome.results.map(\.name), ["Utrecht"])
        XCTAssertNil(outcome.message)
    }
}
