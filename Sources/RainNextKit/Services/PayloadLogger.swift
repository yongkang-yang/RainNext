// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Keeps raw Buienradar responses so the thresholds can eventually be measured
/// instead of guessed (BD-108).
///
/// Only wet payloads are kept: dry ones are the overwhelming majority and carry
/// no information for calibration. Everything stays on this machine.
public struct PayloadLogger: Sendable {
    public let directory: URL
    /// Oldest files are dropped past this, so an unattended app cannot fill a disk.
    public let fileLimit: Int

    public init?(directory: URL? = nil, fileLimit: Int = 500) {
        guard let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RainNext/payloads", isDirectory: true)
        else { return nil }

        self.directory = base
        self.fileLimit = fileLimit
    }

    /// Stores `data` unchanged if it contains any precipitation at all.
    public func record(_ data: Data, location: WeatherLocation, at date: Date) {
        guard containsRain(data) else { return }

        let name = "\(Self.stamp(date))_\(String(format: "%.2f_%.2f", location.latitude, location.longitude)).json"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            prune()
        } catch {
            // Calibration data is a nice-to-have; never fail a refresh over it.
        }
    }

    private func containsRain(_ data: Data) -> Bool {
        guard let readings = try? BuienradarForecastParser.parse(data) else { return false }
        return readings.contains { $0.millimetersPerHour > 0 }
    }

    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ), files.count > fileLimit else { return }

        let sorted = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left < right
        }
        for file in sorted.prefix(files.count - fileLimit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        formatter.timeZone = .gmt
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "")
    }
}
