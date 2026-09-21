// SPDX-License-Identifier: GPL-3.0-or-later
import RainNextKit
import SwiftUI

/// The answer, in as few words as possible, plus one supporting line.
struct StatusSummaryView: View {
    let status: RainStatus
    let observation: StationObservation?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.headline(at: now))
                .font(.system(size: 17, weight: .semibold))
            if let detail = status.detail(at: now) {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let observation {
                sky(observation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The sky as the nearest station sees it — the half a precipitation
    /// nowcast cannot answer.
    private func sky(_ observation: StationObservation) -> some View {
        HStack(spacing: 5) {
            Image(systemName: observation.symbolName)
                .font(.system(size: 11))
            Text(observation.condition.label)
            if let temperature = observation.temperature {
                Text("· \(temperature, specifier: "%.0f")°")
            }
            if let bft = observation.windBft, bft > 0 {
                Text("· \(observation.windDirection ?? "") \(bft) Bft")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}
