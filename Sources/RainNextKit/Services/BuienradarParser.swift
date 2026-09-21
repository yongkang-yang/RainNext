import Foundation

/// Parses Buienradar's `raintext` payload:
///
///     000|19:20
///     077|19:25
///
/// Times arrive as bare `HH:mm` in Amsterdam local time, so they are resolved
/// into real `Date`s immediately — carrying the strings around breaks around
/// midnight and makes every duration calculation a special case.
public enum BuienradarParser {
    public static let sourceTimeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt

    public static func parse(_ payload: String, reference: Date, timeZone: TimeZone = sourceTimeZone) -> [RainReading] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var readings: [RainReading] = []
        var previous: Date?

        for line in payload.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|")
            guard parts.count == 2,
                  let value = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let timestamp = date(
                      from: parts[1].trimmingCharacters(in: .whitespaces),
                      after: previous,
                      reference: reference,
                      calendar: calendar
                  )
            else { continue }

            readings.append(RainReading(timestamp: timestamp, rawValue: value))
            previous = timestamp
        }

        return readings
    }

    private static func date(from clock: String, after previous: Date?, reference: Date, calendar: Calendar) -> Date? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        guard let sameDay = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reference) else { return nil }

        guard let previous else {
            // First sample: pick the day that lands closest to now, so a payload
            // starting at 23:55 or 00:05 resolves on the correct side of midnight.
            return [-1, 0, 1]
                .compactMap { calendar.date(byAdding: .day, value: $0, to: sameDay) }
                .min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
        }

        // Later samples only ever move forward.
        var candidate = sameDay
        while candidate <= previous {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return candidate
    }
}
