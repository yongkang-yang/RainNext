// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Persists the selected location and the saved list.
///
/// The saved list is seeded once with the built-in presets rather than starting
/// empty: location permission may be denied or still pending on first launch,
/// and an empty picker with a search field is a worse first run than five
/// deletable cities.
public final class LocationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let selectedKey = "RainNext.selectedLocation"
    private let favouritesKey = "RainNext.favourites"
    private let seededKey = "RainNext.didSeedFavourites"

    /// Past this the picker stops being glanceable, which is the whole point.
    public static let favouritesLimit = 12

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selected: WeatherLocation? {
        get { decode(WeatherLocation.self, forKey: selectedKey) }
        set { encode(newValue, forKey: selectedKey) }
    }

    public var favourites: [WeatherLocation] {
        get { decode([WeatherLocation].self, forKey: favouritesKey) ?? [] }
        set { encode(Array(newValue.prefix(Self.favouritesLimit)), forKey: favouritesKey) }
    }

    /// Fills the list on first launch only, so deleting every entry sticks.
    @discardableResult
    public func seedIfNeeded() -> [WeatherLocation] {
        guard !defaults.bool(forKey: seededKey) else { return favourites }
        favourites = WeatherLocation.presets
        defaults.set(true, forKey: seededKey)
        return favourites
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
