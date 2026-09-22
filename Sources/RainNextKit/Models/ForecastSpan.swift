// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// How far ahead the timeline looks.
///
/// Two hours is the radar nowcast: echoes that exist, moved forward. Anything
/// longer is Buienradar's hourly model output, which is a different kind of
/// number — it knows about rain that has not formed yet, and it is wrong in
/// different ways. The app labels which one is on screen instead of blending
/// them, because "rain at 18:00" has not earned the trust "rain in 20 minutes"
/// has.
public enum ForecastSpan: String, CaseIterable, Identifiable, Codable, Sendable {
    case twoHours
    case twelveHours
    case twoDays

    public var id: String { rawValue }

    /// Picker text, short enough for a segmented control in a 320pt popover.
    public var label: String {
        switch self {
        case .twoHours: return "2h"
        case .twelveHours: return "12h"
        case .twoDays: return "48h"
        }
    }

    public var title: String {
        switch self {
        case .twoHours: return "Next 2 hours"
        case .twelveHours: return "Next 12 hours"
        case .twoDays: return "Next 48 hours"
        }
    }

    /// Named on screen, so a glance can tell radar from model.
    public var sourceLabel: String { isNowcast ? "radar" : "hourly forecast" }

    public var duration: TimeInterval {
        switch self {
        case .twoHours: return ForecastWindow.horizon
        case .twelveHours: return 12 * 3600
        case .twoDays: return 48 * 3600
        }
    }

    /// The nowcast answers this span; the others need the hourly feed.
    public var isNowcast: Bool { self == .twoHours }
}
