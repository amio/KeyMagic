import SwiftUI

/// A shared table header used in ApplicationsView and ScriptsView.
struct ListTableHeader<Content: View>: View {
    var trailingPadding: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.leading, 20)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A shared row container used in ApplicationsView and ScriptsView.
/// Provides zebra-stripe background, hover highlight, and consistent padding.
/// Pass `isOdd` from the enclosing ForEach index to alternate row tints.
struct ListRowContainer<Content: View>: View {
    /// Whether this is an odd-indexed row — drives the zebra stripe.
    var isOdd: Bool = false
    /// Optional accent tint applied beneath the hover/stripe layers (e.g. for bound-app rows).
    var accentBackground: Color = .clear
    /// Vertical padding inside the row. Defaults to 6; use 8 for rows with taller content.
    var verticalPadding: CGFloat = 6
    /// Trailing padding after the final column. Defaults to the shared 20-point table inset.
    var trailingPadding: CGFloat = 20

    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.leading, 20)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        ZStack {
            // Persistent accent tint (e.g. for bound-app rows in ApplicationsView)
            accentBackground

            // Zebra stripe — odd rows get a very subtle tint
            if isOdd {
                Color.primary.opacity(0.03)
            }

            // Hover highlight — slightly stronger, appears on top of stripe
            if isHovered {
                Color.primary.opacity(0.05)
            }
        }
    }
}
