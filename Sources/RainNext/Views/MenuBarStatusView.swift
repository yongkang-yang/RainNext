import RainNextKit
import SwiftUI

/// The menu bar item itself: a symbol, optionally followed by a countdown or a rate.
struct MenuBarStatusView: View {
    let state: MenuBarState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: state.symbolName)
            if let text = state.text {
                Text(text)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .accessibilityLabel(state.accessibilityLabel)
    }
}
