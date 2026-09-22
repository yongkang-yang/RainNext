// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Liquid Glass where the system has it, a quiet fill where it does not.
///
/// The package still deploys to macOS 14, so every glass call sits behind an
/// availability check here rather than scattered through the views. Glass is
/// for things you press — the location pill, the footer buttons, the search
/// field. The forecast itself is content, and sits on a plain rounded fill:
/// glass on glass inside a popover that is already glass only muddies it.
extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(Color.primary.opacity(0.07), in: shape)
        }
    }

    /// A content card: continuous corners, no glass.
    func card(cornerRadius: CGFloat = Metrics.cardRadius) -> some View {
        background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

/// Lets neighbouring glass shapes blend into each other instead of stacking
/// as separate panes.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A round glass button holding one symbol.
struct GlassIconButton: View {
    let symbol: String
    let help: String
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .opacity(dimmed ? 0.4 : 1)
                .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                .contentShape(Circle())
                .glassSurface(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The card's corner is concentric with the popover's: its radius is the
/// popover's minus the padding between them, so the two curves run parallel.
enum Metrics {
    static let popoverWidth: CGFloat = 360
    static let popoverRadius: CGFloat = 28
    static let popoverPadding: CGFloat = 16
    static let cardRadius: CGFloat = popoverRadius - popoverPadding
    static let cardPadding: CGFloat = 12
    static let chartRadius: CGFloat = 6
    static let iconButton: CGFloat = 28
    static let searchHeight: CGFloat = 32
    static let rowHeight: CGFloat = 28
    static let rowInset: CGFloat = 6
    static let rowRadius: CGFloat = cardRadius - rowInset
    static let listInset: CGFloat = 8
}

/// Rounds the MenuBarExtra window itself.
///
/// SwiftUI offers no way to shape that window, and its stock corner is far
/// tighter than the rest of macOS 26. Masking the frame view's layer rounds
/// the material, but not the shadow: the window server still casts it from
/// the window's own corner radius, which leaves square corners showing on a
/// light desktop. Only the window can change that radius, and only through
/// `_setCornerRadius:`, which is private. It is looked up at runtime, so if a
/// future macOS drops it the content stays rounded and the shadow goes back
/// to the stock shape. Nothing breaks.
struct PopoverWindowShape: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView { Probe(cornerRadius: cornerRadius) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        let cornerRadius: CGFloat

        init(cornerRadius: CGFloat) {
            self.cornerRadius = cornerRadius
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let frame = window.contentView?.superview else { return }
            frame.wantsLayer = true
            frame.layer?.cornerRadius = cornerRadius
            frame.layer?.cornerCurve = .continuous
            frame.layer?.masksToBounds = true

            let setCornerRadius = NSSelectorFromString("_setCornerRadius:")
            if window.responds(to: setCornerRadius) {
                typealias Setter = @convention(c) (NSWindow, Selector, CGFloat) -> Void
                unsafeBitCast(window.method(for: setCornerRadius), to: Setter.self)(window, setCornerRadius, cornerRadius)
            }
            window.invalidateShadow()
        }
    }
}
