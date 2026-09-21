// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import CoreLocation
import Foundation

/// Turns typed text into locations, using the geocoder already on the system —
/// no extra dependency, no API key.
///
/// Results outside Buienradar's coverage are dropped rather than shown and
/// rejected later: offering "Paris" and then refusing it is worse than never
/// offering it. The endpoint still has the final say when a place is added.
@MainActor
public final class PlaceSearchService: ObservableObject {
    @Published public private(set) var results: [WeatherLocation] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var message: String?

    private let geocoder = CLGeocoder()
    private var task: Task<Void, Never>?

    /// Typing is faster than geocoding, and the geocoder is rate limited.
    private let debounce: Duration = .milliseconds(350)

    public init() {}

    public static let noResults = "No places found."
    public static let outsideCoverage = "Outside Buienradar's coverage."

    public struct Outcome: Equatable, Sendable {
        public let results: [WeatherLocation]
        public let message: String?
    }

    /// Pure so the "found nothing" and "found only uncovered places" cases can
    /// be told apart in a test without going near the geocoder.
    nonisolated public static func outcome(forFound found: [WeatherLocation]) -> Outcome {
        let covered = found.filter(BuienradarCoverage.contains)
        guard covered.isEmpty else { return Outcome(results: covered, message: nil) }
        return Outcome(results: [], message: found.isEmpty ? noResults : outsideCoverage)
    }

    public func search(_ query: String) {
        task?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            message = nil
            isSearching = false
            return
        }

        task = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmed)
        }
    }

    public func clear() {
        task?.cancel()
        results = []
        message = nil
        isSearching = false
    }

    private func performSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }

        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.geocodeAddressString(query)
        } catch {
            guard !Task.isCancelled else { return }
            // A geocoder "no result" is not worth an alarming error message.
            results = []
            message = (error as? CLError)?.code == .geocodeFoundNoResult
                ? Self.noResults
                : error.localizedDescription
            return
        }
        guard !Task.isCancelled else { return }

        let outcome = Self.outcome(forFound: placemarks.compactMap(Self.location(from:)))
        results = outcome.results
        message = outcome.message
    }

    private static func location(from placemark: CLPlacemark) -> WeatherLocation? {
        guard let coordinate = placemark.location?.coordinate else { return nil }

        let primary = placemark.locality ?? placemark.name ?? placemark.subAdministrativeArea
        guard let primary else { return nil }
        // Enough context to tell two same-named towns apart.
        let context = [placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .filter { $0 != primary }
            .first

        return WeatherLocation(
            name: context.map { "\(primary), \($0)" } ?? primary,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: .custom
        )
    }
}
