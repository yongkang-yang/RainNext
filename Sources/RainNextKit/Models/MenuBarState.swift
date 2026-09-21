// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the menu bar shows. Kept out of the views so the notation is testable
/// and can be changed in one place — the exact wording is still open (BD-105).
///
/// Current notation:
///
///     ☀            dry for the whole window
///     ☂ 27m        rain starts in 27 minutes
///     ☂ 0.8        raining now at ~0.8 mm/h
public struct MenuBarState: Equatable, Sendable {
    public let symbolName: String
    public let text: String?
    public let accessibilityLabel: String

    public init(symbolName: String, text: String?, accessibilityLabel: String) {
        self.symbolName = symbolName
        self.text = text
        self.accessibilityLabel = accessibilityLabel
    }

    /// Rain further out than this is not worth a countdown in the menu bar.
    public static let countdownHorizon: TimeInterval = 90 * 60

    private static func sky(_ observation: StationObservation) -> MenuBarState {
        MenuBarState(
            symbolName: observation.symbolName,
            text: nil,
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
                return MenuBarState(symbolName: "cloud.slash", text: nil, accessibilityLabel: "RainNext: no data")
            }
            return sky(observation)

        case .dry(let next):
            // `isAnnounceable` gates predictions, not observations: a forecast
            // that fails to arrive costs trust, a rate being shown right now
            // cannot be wrong in the same way.
            guard let next, next.isAnnounceable,
                  next.start.timeIntervalSince(now) <= countdownHorizon else {
                guard let observation else {
                    return MenuBarState(symbolName: "sun.max", text: nil, accessibilityLabel: "RainNext: dry")
                }
                return sky(observation)
            }
            let minutes = max(0, Int((next.start.timeIntervalSince(now) / 60).rounded()))
            return MenuBarState(
                symbolName: next.peak == .heavy ? "cloud.heavyrain" : "umbrella",
                text: "\(minutes)m",
                accessibilityLabel: "RainNext: rain in \(minutes) minutes"
            )

        case .raining(_, let intensity):
            return MenuBarState(
                symbolName: RainIntensity(millimetersPerHour: intensity) == .heavy ? "cloud.heavyrain.fill" : "umbrella.fill",
                text: String(format: "%.1f", intensity),
                accessibilityLabel: "RainNext: raining, \(RainPhrasing.rate(intensity))"
            )
        }
    }
}
