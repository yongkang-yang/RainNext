// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import CoreLocation
import Foundation

/// Coarse current location, plus a human-readable name for it.
///
/// Weather does not need building-level accuracy, so this asks for reduced
/// accuracy only and never starts continuous updates.
@MainActor
public final class LocationService: NSObject, ObservableObject {
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus
    @Published public private(set) var currentLocation: WeatherLocation?
    @Published public private(set) var failure: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    public override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    public var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
    }

    public func requestAuthorization() {
        guard authorizationStatus == .notDetermined else {
            refresh()
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    public func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    private func adopt(_ location: CLLocation) {
        let coordinate = location.coordinate
        currentLocation = WeatherLocation.current(
            name: currentLocation?.name ?? "Current location",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        failure = nil
        resolveName(for: location)
    }

    private func resolveName(for location: CLLocation) {
        Task { [weak self] in
            guard let placemark = try? await self?.geocoder.reverseGeocodeLocation(location).first else { return }
            let name = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
            guard let name, let self, var updated = self.currentLocation else { return }
            updated.name = name
            self.currentLocation = updated
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.refresh()
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.adopt(location) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.failure = message }
    }
}
