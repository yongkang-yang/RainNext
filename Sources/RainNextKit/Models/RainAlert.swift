// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A notification worth sending, and the text to send.
public struct RainAlert: Equatable, Sendable {
    public let title: String
    public let body: String
    /// The episode this warns about, so the ledger can avoid repeating itself.
    public let episodeStart: Date
    public let episodeEnd: Date

    public init(title: String, body: String, episodeStart: Date, episodeEnd: Date) {
        self.title = title
        self.body = body
        self.episodeStart = episodeStart
        self.episodeEnd = episodeEnd
    }
}

/// Decides whether rain is worth interrupting someone for, without scheduling
/// anything. Pure, so every rule below is testable.
public enum RainAlertPlanner {
    /// Announce once rain is this close. With a five-minute refresh the actual
    /// lead time lands between 15 and 20 minutes — enough to grab a coat or
    /// change plans, and close enough in that the nowcast is worth trusting.
    public static let horizon: TimeInterval = 20 * 60

    /// A floor on how often the app may interrupt, whatever the sky does.
    public static let minimumInterval: TimeInterval = 20 * 60

    /// What has already been said, so a forecast that shifts by a few minutes
    /// between refreshes does not announce the same shower twice.
    public struct Ledger: Equatable, Sendable {
        public var lastNotifiedAt: Date?
        /// End of the episode already announced. Anything starting before this
        /// is the same weather, however much its start time has drifted.
        public var coveredThrough: Date?

        public init(lastNotifiedAt: Date? = nil, coveredThrough: Date? = nil) {
            self.lastNotifiedAt = lastNotifiedAt
            self.coveredThrough = coveredThrough
        }

        public mutating func record(_ alert: RainAlert, at now: Date) {
            lastNotifiedAt = now
            coveredThrough = alert.episodeEnd
        }
    }

    public static func alert(for forecast: RainForecast, at now: Date, ledger: Ledger) -> RainAlert? {
        // Telling someone it is about to rain while they are already in it is
        // the fastest way to get the app muted.
        guard case .dry(let upcoming) = forecast.status(at: now), let episode = upcoming else { return nil }

        // The same floor the menu bar uses: never notify about rain the app
        // would not even put a countdown on.
        guard episode.isAnnounceable else { return nil }

        let lead = episode.start.timeIntervalSince(now)
        guard lead > 0, lead <= horizon else { return nil }

        if let last = ledger.lastNotifiedAt, now.timeIntervalSince(last) < minimumInterval { return nil }
        if let covered = ledger.coveredThrough, episode.start < covered { return nil }

        return RainAlert(
            title: "\(episode.peak.label) in \(RainPhrasing.minutes(from: now, to: episode.start))",
            body: "About \(RainPhrasing.duration(episode.duration)), until \(RainPhrasing.clock(episode.end)).",
            episodeStart: episode.start,
            episodeEnd: episode.end
        )
    }
}
