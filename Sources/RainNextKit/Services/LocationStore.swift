// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Remembers the selected location so the first frame after launch is useful
/// before CoreLocation has answered.
public final class LocationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "RainNext.selectedLocation"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selected: WeatherLocation? {
        get {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(WeatherLocation.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(data, forKey: key)
        }
    }
}
