// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The menu bar shows only a weather symbol; details remain available to accessibility.
public struct MenuBarState: Equatable, Sendable {
    public let symbolName: String
    public let accessibilityLabel: String

    public init(symbolName: String, accessibilityLabel: String) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
    }

    /// Rain further out than this is not worth showing in the menu bar.
    public static let upcomingRainHorizon: TimeInterval = 90 * 60

    private static func sky(_ observation: StationObservation) -> MenuBarState {
        MenuBarState(
            symbolName: observation.symbolName,
            accessibilityLabel: "RainNext: \(observation.condition.label.lowercased())"
        )
    }

    /// `observation` fills the gap the nowcast leaves — everything that is not
    /// rain. It never overrides the nowcast: rain is what this app is for, and
    /// a station reporting "cloudy" while rain is falling would be a downgrade.
    public static func make(
        from status: RainStatus,
        observation: StationObservation? = nil,
        at now: Date
    ) -> MenuBarState {
        switch status {
        case .unavailable:
            guard let observation else {
                return MenuBarState(symbolName: "cloud.slash", accessibilityLabel: "RainNext: no data")
            }
            return sky(observation)

        case .dry(let next):
            // `isAnnounceable` gates predictions, not observations: a forecast
            // that fails to arrive costs trust, a rate being shown right now
            // cannot be wrong in the same way.
            guard let next, next.isAnnounceable,
                  next.start.timeIntervalSince(now) <= upcomingRainHorizon else {
                guard let observation else {
                    return MenuBarState(symbolName: "sun.max", accessibilityLabel: "RainNext: dry")
                }
                return sky(observation)
            }
            let minutes = max(0, Int((next.start.timeIntervalSince(now) / 60).rounded()))
            return MenuBarState(
                symbolName: next.peak == .heavy ? "cloud.heavyrain" : "cloud.rain",
                accessibilityLabel: "RainNext: rain in \(minutes) minutes"
            )

        case .raining(_, let intensity):
            return MenuBarState(
                symbolName: RainIntensity(millimetersPerHour: intensity) == .heavy ? "cloud.heavyrain.fill" : "cloud.rain.fill",
                accessibilityLabel: "RainNext: raining, \(RainPhrasing.rate(intensity))"
            )
        }
    }
}
