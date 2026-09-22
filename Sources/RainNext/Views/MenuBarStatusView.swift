// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import RainNextKit
import SwiftUI

/// The menu bar item itself: a symbol, optionally followed by a countdown or a rate.
struct MenuBarStatusView: View {
    let state: MenuBarState

    var body: some View {
        HStack(spacing: 3) {
            symbol
            if let text = state.text {
                Text(text)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
        }
        .accessibilityLabel(state.accessibilityLabel)
    }

    /// The menu bar ignores SwiftUI font modifiers on a label's image and
    /// draws symbols at its own small default, so the size is baked into the
    /// NSImage instead. Template, so it still follows the menu bar's colour.
    private var symbol: Image {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        guard let image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return Image(systemName: state.symbolName)
        }
        image.isTemplate = true
        return Image(nsImage: image)
    }
}
