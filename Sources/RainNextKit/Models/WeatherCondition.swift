// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The sky, coarse enough to be read at a glance in a menu bar.
///
/// Buienradar publishes a condition as a two-variant icon code: 22 conditions
/// as single letters `a`–`w` (there is no `e`), and the same letters doubled
/// for night — `a` is a sun, `aa` a moon. The codes are matched rather than the
/// Dutch description, because a code is an identifier and a sentence is not.
public enum WeatherCondition: String, Sendable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain
    case thunder
    case snow
    case sleet
    case unknown

    /// Read off the published icon set, one code at a time.
    private static let byCode: [Character: WeatherCondition] = [
        "a": .clear,
        "b": .partlyCloudy, "j": .partlyCloudy, "r": .partlyCloudy,
        "c": .cloudy, "p": .cloudy,
        "d": .fog, "n": .fog, "o": .fog,
        "f": .drizzle, "m": .drizzle,
        "h": .rain, "k": .rain, "q": .rain,
        "l": .heavyRain,
        "g": .thunder, "s": .thunder,
        "i": .snow, "t": .snow, "u": .snow, "v": .snow,
        "w": .sleet,
    ]

    public init(iconCode code: String) {
        let letters = code.lowercased().filter(\.isLetter)
        guard let first = letters.first, let condition = Self.byCode[first] else {
            self = .unknown
            return
        }
        self = condition
    }

    /// Night is the doubled form of the same code. Taking it from the provider
    /// rather than from sunrise arithmetic keeps the app agreeing with the
    /// source it is quoting.
    public static func isNight(iconCode code: String) -> Bool {
        code.lowercased().filter(\.isLetter).count >= 2
    }

    public func symbolName(isNight: Bool) -> String {
        switch self {
        case .clear: return isNight ? "moon.stars" : "sun.max"
        case .partlyCloudy: return isNight ? "cloud.moon" : "cloud.sun"
        case .cloudy: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .thunder: return "cloud.bolt.rain"
        case .snow: return "cloud.snow"
        case .sleet: return "cloud.sleet"
        case .unknown: return "cloud"
        }
    }

    public var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy rain"
        case .thunder: return "Thunderstorms"
        case .snow: return "Snow"
        case .sleet: return "Sleet"
        case .unknown: return "Unknown"
        }
    }
}
