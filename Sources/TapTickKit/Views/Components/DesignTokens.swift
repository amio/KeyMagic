import SwiftUI

enum SettingsLayout {
    static let toolbarTitleLeadingPadding: CGFloat = 12
}

struct SettingsToolbarTitle: View {
    let title: String

    var body: some View {
        SettingsToolbarItemLayout {
            Text(title)
                .font(.headline)
                .padding(.leading, SettingsLayout.toolbarTitleLeadingPadding)
        }
    }
}

/// Keeps dynamic custom toolbar content on a stable leading pixel boundary.
///
/// AppKit centers SwiftUI toolbar views inside an integer-width item container. A
/// half-point ideal width therefore moves the hosted view by half a point. Rounding
/// only the outer width preserves the content's natural layout and leading alignment.
struct SettingsToolbarItemLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = subview.sizeThatFits(proposal)
        return CGSize(width: size.width.rounded(.up), height: size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(proposal)
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(size)
        )
    }
}

// MARK: - View Extensions

extension View {
    /// Applies the standard TapTick grouped-form style.
    ///
    /// Use this instead of a bare `.formStyle(.grouped)` on every settings `Form`.
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
    }
}
