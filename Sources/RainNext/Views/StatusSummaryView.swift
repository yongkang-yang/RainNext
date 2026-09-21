import RainNextKit
import SwiftUI

/// The answer, in as few words as possible, plus one supporting line.
struct StatusSummaryView: View {
    let status: RainStatus
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
