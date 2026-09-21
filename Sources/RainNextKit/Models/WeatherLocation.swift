// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct WeatherLocation: Identifiable, Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case current
        case preset
        case custom
    }

    public let id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var source: Source

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, source: Source) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
    }

    public var isCurrentLocation: Bool { source == .current }

    /// Stable id so "current location" stays the same selection across launches
    /// even as its coordinates move with the user.
    public static let currentLocationID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    public static func current(name: String, latitude: Double, longitude: Double) -> WeatherLocation {
        WeatherLocation(id: currentLocationID, name: name, latitude: latitude, longitude: longitude, source: .current)
    }

    /// Buienradar only covers the Benelux, so the presets stay there for now.
    public static let presets: [WeatherLocation] = [
        WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Amsterdam", latitude: 52.3676, longitude: 4.9041, source: .preset),
        WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Utrecht", latitude: 52.0907, longitude: 5.1214, source: .preset),
        WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Rotterdam", latitude: 51.9244, longitude: 4.4777, source: .preset),
        WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "The Hague", latitude: 52.0705, longitude: 4.3007, source: .preset),
        WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Eindhoven", latitude: 51.4416, longitude: 5.4697, source: .preset),
    ]

    /// Used before location permission resolves, so the app always has something to show.
    public static let fallback = presets[0]
}
