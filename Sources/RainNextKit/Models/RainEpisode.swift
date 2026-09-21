import Foundation

/// A continuous stretch of rain, derived from consecutive wet readings.
///
/// This is the model the UI talks in — "rain in 18 min", "rain for ~35 min",
/// "stops around 19:40" are all questions about an episode, not about a sample.
public struct RainEpisode: Identifiable, Hashable, Sendable {
    public let start: Date
    /// Exclusive end: the moment the last wet sample's slot runs out.
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

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Intensity of the sample covering `date`, or the nearest one inside the episode.
    public func intensity(at date: Date) -> Double {
        let covering = readings.last { $0.timestamp <= date }
        return (covering ?? readings.first)?.millimetersPerHour ?? 0
    }

    /// Groups readings into episodes, bridging single dropped samples.
    public static func episodes(from readings: [RainReading]) -> [RainEpisode] {
        var episodes: [RainEpisode] = []
        var current: [RainReading] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            episodes.append(
                RainEpisode(
                    start: first.timestamp,
                    end: last.timestamp.addingTimeInterval(RainThresholds.sampleInterval),
                    readings: current
                )
            )
            current = []
        }

        for reading in readings.sorted(by: { $0.timestamp < $1.timestamp }) {
            if reading.isRaining {
                current.append(reading)
            } else {
                flush()
            }
        }
        flush()

        return merge(episodes)
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
