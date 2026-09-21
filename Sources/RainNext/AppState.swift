// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation
import RainNextKit

/// Owns the refresh cadence and the currently selected location, and hands the
/// views a ready-made status. The domain logic itself lives in RainNextKit.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var forecast: RainForecast?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var now = Date()
    @Published private(set) var selectedLocation: WeatherLocation
    @Published private(set) var favourites: [WeatherLocation]
    /// Set when CoreLocation puts the user somewhere Buienradar cannot see.
    @Published private(set) var currentLocationIsCovered = true

    let locationService = LocationService()
    let placeSearch = PlaceSearchService()

    private let rainService: RainDataSource
    private let store = LocationStore()
    private var prefersCurrentLocation: Bool
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Background cadence from BD-105.
    static let refreshInterval: TimeInterval = 5 * 60
    /// Opening the popover only re-fetches if the data has had time to move.
    static let openRefreshInterval: TimeInterval = 60

    init(rainService: RainDataSource = BuienradarRainService()) {
        self.rainService = rainService
        let saved = store.selected
        self.selectedLocation = saved ?? .fallback
        self.prefersCurrentLocation = saved?.isCurrentLocation ?? true
        self.favourites = store.seedIfNeeded()

        locationService.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in self?.currentLocationChanged(to: location) }
            .store(in: &cancellables)

        locationService.requestAuthorization()
        startTicking()
        refresh()
    }

    deinit {
        refreshTask?.cancel()
        tickTask?.cancel()
    }

    var status: RainStatus { forecast?.status(at: now) ?? .unavailable }
    var menuBarState: MenuBarState { MenuBarState.make(from: status, at: now) }

    var canAddFavourite: Bool { favourites.count < LocationStore.favouritesLimit }

    func isSaved(_ location: WeatherLocation) -> Bool {
        favourites.contains { $0.id == location.id || $0.isSamePlace(as: location) }
    }

    func addFavourite(_ location: WeatherLocation) {
        guard canAddFavourite, !isSaved(location) else {
            select(location)
            return
        }
        favourites.append(location)
        store.favourites = favourites
        select(location)
    }

    func removeFavourites(at offsets: IndexSet) {
        let removed = offsets.map { favourites[$0] }
        favourites.remove(atOffsets: offsets)
        store.favourites = favourites

        // Dropping the place you were looking at should land somewhere sensible
        // rather than leaving a stale name in the header.
        if removed.contains(where: { $0.id == selectedLocation.id }) {
            select(locationService.currentLocation ?? favourites.first ?? .fallback)
        }
    }

    func moveFavourites(from source: IndexSet, to destination: Int) {
        favourites.move(fromOffsets: source, toOffset: destination)
        store.favourites = favourites
    }

    func select(_ location: WeatherLocation) {
        prefersCurrentLocation = location.isCurrentLocation
        selectedLocation = location
        store.selected = location
        if location.isCurrentLocation { locationService.refresh() }
        refresh()
    }

    /// `minimumAge` of 0 always fetches; otherwise the current forecast is kept
    /// if it is still fresh enough.
    func refresh(minimumAge: TimeInterval = 0) {
        if minimumAge > 0, let fetchedAt = forecast?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < minimumAge {
            now = Date()
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.performRefresh() }
    }

    private func performRefresh() async {
        let location = selectedLocation
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await rainService.fetchForecast(for: location, now: Date())
            guard !Task.isCancelled else { return }
            forecast = result
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            // Keep the last valid reading on screen; a failed refresh is not a
            // reason to go blank.
            errorMessage = error.localizedDescription
        }
        now = Date()
    }

    private func currentLocationChanged(to location: WeatherLocation) {
        currentLocationIsCovered = BuienradarCoverage.contains(location)
        // Following the user to a place the radar cannot see would replace a
        // working forecast with a permanent error. Stay put instead.
        guard currentLocationIsCovered else { return }
        guard prefersCurrentLocation else { return }
        let moved = abs(location.latitude - selectedLocation.latitude) > 0.01
            || abs(location.longitude - selectedLocation.longitude) > 0.01
        selectedLocation = location
        store.selected = location
        if moved || forecast == nil { refresh() }
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                await MainActor.run {
                    self.now = Date()
                    self.refresh(minimumAge: Self.refreshInterval)
                }
            }
        }
    }
}
