// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A continuous stretch of rain, derived from consecutive wet samples.
///
/// This is the model the UI talks in — "rain in 18 min", "rain for ~35 min",
/// "stops around 19:40" are all questions about an episode, not about a sample.
public struct RainEpisode: Identifiable, Hashable, Sendable {
    public let start: Date
    /// Exclusive: the moment the last wet sample's slot runs out.
    public let end: Date
    public let readings: [RainReading]

    public init(start: Date, end: Date, readings: [RainReading]) {
        self.start = start
        self.end = end
        self.readings = readings
    }

    public var id: Date { start }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public var peakIntensity: Double {
        readings.map(\.millimetersPerHour).max() ?? 0
    }

    public var peak: RainIntensity {
        RainIntensity(millimetersPerHour: peakIntensity)
    }

    /// Whether this is worth interrupting someone for. Drizzle is real, and
    /// belongs on the graph, but it does not belong in the menu bar.
    public var isAnnounceable: Bool {
        peakIntensity >= RainThresholds.announceFloor
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Intensity of the sample covering `date`, or the nearest one inside the episode.
    public func intensity(at date: Date) -> Double {
        let covering = readings.last { $0.timestamp <= date }
        return (covering ?? readings.first)?.millimetersPerHour ?? 0
    }

    /// Groups readings into episodes: bridge short dry gaps, then drop anything
    /// too brief to be real.
    ///
    /// Sample spacing is taken from the data rather than assumed — Buienradar
    /// payloads do drop slots, and a missing slot must not silently shift every
    /// timestamp after it.
    public static func episodes(from readings: [RainReading]) -> [RainEpisode] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        var episodes: [RainEpisode] = []
        var current: [RainReading] = []
        var currentEnd = Date.distantPast

        func flush() {
            guard let first = current.first else { return }
            episodes.append(RainEpisode(start: first.timestamp, end: currentEnd, readings: current))
            current = []
        }

        for (index, reading) in sorted.enumerated() {
            guard reading.isRaining else {
                flush()
                continue
            }
            current.append(reading)
            currentEnd = slotEnd(at: index, in: sorted)
        }
        flush()

        return merge(episodes).filter { $0.duration >= RainThresholds.minimumEpisodeDuration }
    }

    /// A sample's slot runs until the next sample. If the feed skipped a slot,
    /// the unknown stretch is capped rather than assumed to be wet throughout.
    private static func slotEnd(at index: Int, in readings: [RainReading]) -> Date {
        let timestamp = readings[index].timestamp
        let cap = timestamp.addingTimeInterval(2 * RainThresholds.sampleInterval)
        guard index + 1 < readings.count else {
            return timestamp.addingTimeInterval(RainThresholds.sampleInterval)
        }
        return min(readings[index + 1].timestamp, cap)
    }

    private static func merge(_ episodes: [RainEpisode]) -> [RainEpisode] {
        guard var previous = episodes.first else { return [] }
        var merged: [RainEpisode] = []

        for episode in episodes.dropFirst() {
            if episode.start.timeIntervalSince(previous.end) <= RainThresholds.episodeMergeGap {
                previous = RainEpisode(
                    start: previous.start,
                    end: episode.end,
                    readings: previous.readings + episode.readings
                )
            } else {
                merged.append(previous)
                previous = episode
            }
        }
        merged.append(previous)
        return merged
    }
}
