import SwiftUI

// MARK: - View Extensions

extension View {
    /// Applies the standard TapTick grouped-form style.
    ///
    /// Use this instead of a bare `.formStyle(.grouped)` on every settings `Form`.
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
    }
}