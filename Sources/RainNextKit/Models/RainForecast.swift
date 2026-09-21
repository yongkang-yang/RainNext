// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// How much of the feed the app actually shows.
///
/// Buienradar's JSON feed carries both history and a forecast that runs past
/// two hours; RainNext is a near-term app, so it trims both ends. The history
/// is there so the NOW marker sits inside the graph rather than on its left
/// edge — "it has been raining for 20 minutes and stops in 15" needs the past.
public enum ForecastWindow {
    public static let history: TimeInterval = 30 * 60
    public static let horizon: TimeInterval = 2 * 60 * 60

    public static func range(around now: Date) -> ClosedRange<Date> {
        now.addingTimeInterval(-history)...now.addingTimeInterval(horizon)
    }
}

/// Everything one fetch produced: the raw samples, the episodes derived from
/// them, and when it was fetched.
public struct RainForecast: Equatable, Sendable {
    public let location: WeatherLocation
    public let readings: [RainReading]
    public let episodes: [RainEpisode]
    public let fetchedAt: Date

    public init(location: WeatherLocation, readings: [RainReading], fetchedAt: Date) {
        self.location = location
        self.readings = readings.sorted { $0.timestamp < $1.timestamp }
        self.episodes = RainEpisode.episodes(from: readings)
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool { readings.isEmpty }
    public var start: Date? { readings.first?.timestamp }
    public var end: Date? {
        readings.last?.timestamp.addingTimeInterval(RainThresholds.sampleInterval)
    }

    public func status(at date: Date) -> RainStatus {
        guard !readings.isEmpty else { return .unavailable }

        if let active = episodes.first(where: { $0.contains(date) }) {
            return .raining(episode: active, intensity: active.intensity(at: date))
        }
        return .dry(next: episodes.first { $0.start > date })
    }
}

public enum RainStatus: Equatable, Sendable {
    case unavailable
    case dry(next: RainEpisode?)
    case raining(episode: RainEpisode, intensity: Double)

    /// One short line: the answer to "do I need a coat right now?"
    public func headline(at now: Date) -> String {
        switch self {
        case .unavailable:
            return "No data"
        case .dry(let next):
            guard let next else { return "Dry for the next 2 hours" }
            return "Rain in \(RainPhrasing.minutes(from: now, to: next.start))"
        case .raining(_, let intensity):
            return RainIntensity(millimetersPerHour: intensity).label
        }
    }

    /// The supporting line: how long, and until when.
    public func detail(at now: Date) -> String? {
        switch self {
        case .unavailable:
            return nil
        case .dry(let next):
            guard let next else { return nil }
            return "\(next.peak.label), about \(RainPhrasing.duration(next.duration)), until \(RainPhrasing.clock(next.end))"
        case .raining(let episode, let intensity):
            let rate = RainPhrasing.rate(intensity)
            guard episode.end.timeIntervalSince(now) > 0 else { return rate }
            return "\(rate) · stops around \(RainPhrasing.clock(episode.end))"
        }
    }
}

public enum RainPhrasing {
    public static func minutes(from: Date, to: Date) -> String {
        let minutes = max(0, Int((to.timeIntervalSince(from) / 60).rounded()))
        return "\(minutes) min"
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    public static func rate(_ mmh: Double) -> String {
        String(format: "%.1f mm/h", mmh)
    }

    public static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
