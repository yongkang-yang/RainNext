// SPDX-License-Identifier: GPL-3.0-or-later
import RainNextKit
import SwiftUI

/// Precipitation graph with a span picker, a NOW marker and hover details.
///
/// Two hours is the radar nowcast, drawn with a little history so the NOW
/// marker sits inside the graph instead of pinned to its left edge. The longer
/// spans are hourly model output and carry no history at all — they are a
/// different feed, and the header says so rather than letting one bar chart
/// imply one kind of certainty.
struct RainTimelineView: View {
    let forecast: RainForecast?
    let hourly: HourlyRainForecast?
    @Binding var span: ForecastSpan
    let now: Date

    @State private var hovered: RainReading?

    /// mm/h that fills the chart to the top. One scale across every span, so a
    /// bar height means the same thing whichever one is showing.
    private let fullScale: Double = 4.0
    private let chartHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            spanPicker
            header
            chart
            axis
        }
        // A bar under the pointer belongs to the span that was showing.
        .onChange(of: span) { hovered = nil }
    }

    private var bars: [RainReading] {
        span.isNowcast
            ? forecast?.readings ?? []
            : hourly?.readings(within: span, at: now) ?? []
    }

    private var slot: TimeInterval {
        span.isNowcast ? RainThresholds.sampleInterval : HourlyRainForecast.slot
    }

    private var spanPicker: some View {
        HStack(spacing: 8) {
            Picker("Span", selection: $span) {
                ForEach(ForecastSpan.allCases) { span in
                    Text(span.label).tag(span)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)

            Spacer()

            // Which feed this is. "Rain at 18:00" and "rain in 20 minutes" are
            // not the same claim, and only one of them comes from radar.
            Text(span.sourceLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var header: some View {
        HStack {
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let hovered {
                Text("\(RainPhrasing.clock(hovered.timestamp, relativeTo: now)) · \(RainPhrasing.rate(hovered.millimetersPerHour))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    /// The nowcast span says nothing here that the headline above it has not
    /// already said; the long spans are the only place their own answer fits.
    private var summary: String {
        guard !span.isNowcast else { return span.title }
        return hourly?.summary(within: span, at: now) ?? span.title
    }

    private var chart: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.chartRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.04))

                if bars.isEmpty {
                    Text(span.isNowcast ? "No forecast" : "No hourly forecast yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Rain grows up from the floor, so the bars hang off the
                // bottom edge — not off the top, which is where a topLeading
                // ZStack quietly puts them.
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(bars) { reading in
                        bar(for: reading, isPast: reading.timestamp < now)
                    }
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                // A floor line, so an all-dry window reads as "measured, and
                // dry" rather than as a chart that failed to load.
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                dayMarkers(in: geometry.size)
                nowMarker(in: geometry.size)
            }
        }
        .frame(height: chartHeight)
        // Bars and markers stay inside the chart's own curve.
        .clipShape(RoundedRectangle(cornerRadius: Metrics.chartRadius, style: .continuous))
    }

    private func bar(for reading: RainReading, isPast: Bool) -> some View {
        let fraction = min(1, pow(max(0, reading.millimetersPerHour) / fullScale, 0.5))
        let isHovered = hovered?.id == reading.id
        let opacity = isHovered ? 1 : (isPast ? 0.35 : 0.85)

        return UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
            .fill(color(for: reading.intensity).opacity(opacity))
            .frame(height: max(reading.isRaining ? 3 : 2, chartHeight * fraction))
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
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .position(x: size.width * fraction, y: size.height / 2)
        }
    }

    /// Midnights, so two days of bars do not read as one very long day.
    @ViewBuilder
    private func dayMarkers(in size: CGSize) -> some View {
        if !span.isNowcast, bars.count > 1 {
            let calendar = Calendar.current
            ForEach(bars.indices.filter { calendar.component(.hour, from: bars[$0].timestamp) == 0 }, id: \.self) { index in
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .position(x: size.width * (Double(index) / Double(bars.count)), y: size.height / 2)
            }
        }
    }

    private var nowFraction: Double? {
        guard span.isNowcast, let start = forecast?.start, let end = forecast?.end, end > start else { return nil }
        let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return (0...1).contains(fraction) ? fraction : nil
    }

    private var axis: some View {
        HStack {
            if let first = bars.first {
                Text(RainPhrasing.clock(first.timestamp))
            }
            Spacer()
            if let last = bars.last {
                // The right edge is where the window closes, not a time
                // something happens at — "tomorrow 12:00 AM" means midnight.
                Text(RainPhrasing.boundary(last.timestamp.addingTimeInterval(slot), relativeTo: now))
            }
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.tertiary)
    }
}
