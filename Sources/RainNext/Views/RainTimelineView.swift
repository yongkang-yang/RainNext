// SPDX-License-Identifier: GPL-3.0-or-later
import RainNextKit
import SwiftUI

/// Precipitation graph with a NOW marker and hover details.
///
/// The feed carries a little history, drawn faded before the NOW line, so the
/// marker sits inside the graph instead of pinned to its left edge.
struct RainTimelineView: View {
    let forecast: RainForecast?
    let now: Date

    @State private var hovered: RainReading?

    /// mm/h that fills the chart to the top.
    private let fullScale: Double = 4.0
    private let chartHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            chart
            axis
        }
    }

    private var readings: [RainReading] { forecast?.readings ?? [] }

    private var header: some View {
        HStack {
            Text("Next 2 hours")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let hovered {
                Text("\(RainPhrasing.clock(hovered.timestamp)) · \(RainPhrasing.rate(hovered.millimetersPerHour))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))

                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach(readings) { reading in
                        bar(for: reading, isPast: reading.timestamp < now)
                    }
                }
                .padding(.horizontal, 2)

                nowMarker(in: geometry.size)
            }
        }
        .frame(height: chartHeight)
    }

    private func bar(for reading: RainReading, isPast: Bool) -> some View {
        let fraction = min(1, pow(max(0, reading.millimetersPerHour) / fullScale, 0.5))
        let isHovered = hovered?.id == reading.id
        let opacity = isHovered ? 1 : (isPast ? 0.35 : 0.85)

        return RoundedRectangle(cornerRadius: 1.5)
            .fill(color(for: reading.intensity).opacity(opacity))
            .frame(height: max(reading.isRaining ? 3 : 1, chartHeight * fraction))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovered = inside ? reading : (hovered?.id == reading.id ? nil : hovered)
            }
    }

    private func color(for intensity: RainIntensity) -> Color {
        switch intensity {
        case .dry: return .secondary.opacity(0.35)
        case .light: return .accentColor.opacity(0.55)
        case .moderate: return .accentColor
        case .heavy: return .purple
        }
    }

    @ViewBuilder
    private func nowMarker(in size: CGSize) -> some View {
        if let fraction = nowFraction {
            Rectangle()
                .fill(Color.primary.opacity(0.55))
                .frame(width: 1, height: size.height)
                .offset(x: size.width * fraction)
        }
    }

    private var nowFraction: Double? {
        guard let start = forecast?.start, let end = forecast?.end, end > start else { return nil }
        let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return (0...1).contains(fraction) ? fraction : nil
    }

    private var axis: some View {
        HStack {
            if let start = forecast?.start { Text(RainPhrasing.clock(start)) }
            Spacer()
            if let end = forecast?.end { Text(RainPhrasing.clock(end)) }
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.tertiary)
    }
}
