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

    let locationService = LocationService()

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
