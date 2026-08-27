import AppKit
import Observation
import SwiftUI
@testable import TapTickKit
import Testing

@MainActor
@Suite("Settings Toolbar Layout", .serialized)
struct SettingsToolbarLayoutTests {
    @Test("Tracking separator follows the content divider when the sidebar collapses")
    func trackingSeparatorFollowsCollapsedSidebar() async throws {
        let model = SplitVisibilityModel()
        let hostingController = NSHostingController(
            rootView: SettingsSplitFixture(model: model)
                .frame(minWidth: 880, minHeight: 560)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 1_020, height: 680))
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.alphaValue = 0
        window.orderFront(nil)
        defer { window.close() }

        try await settleLayout()
        try assertSeparatorAlignment(in: window)

        model.visibility = .doubleColumn
        try await settleLayout()
        try assertSeparatorAlignment(in: window)
    }

    private func settleLayout() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    /// Public toolbar APIs expose the tracking item but not its rendered frame, so this
    /// regression test compares the AppKit separator and split-divider views directly.
    private func assertSeparatorAlignment(in window: NSWindow) throws {
        let themeFrame = try #require(window.contentView?.superview)
        let descendants = descendants(of: themeFrame)
        let separator = try #require(
            descendants
                .filter { String(describing: type(of: $0)) == "NSSeparatorToolbarItemView" }
                .max { left, right in
                    left.convert(left.bounds, to: nil).midX
                        < right.convert(right.bounds, to: nil).midX
                }
        )
        let contentDivider = try #require(
            descendants
                .filter {
                    String(describing: type(of: $0)) == "NSSplitDividerView"
                        && $0.frame.width >= 4
                }
                .max { left, right in
                    left.convert(left.bounds, to: nil).midX
                        < right.convert(right.bounds, to: nil).midX
                }
        )

        let separatorX = separator.convert(separator.bounds, to: nil).midX
        let dividerX = contentDivider.convert(contentDivider.bounds, to: nil).midX
        #expect(abs(separatorX - dividerX) <= 0.5)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
@Observable
private final class SplitVisibilityModel {
    var visibility = NavigationSplitViewVisibility.all
}

private struct SettingsSplitFixture: View {
    @Bindable var model: SplitVisibilityModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.visibility) {
            List {
                Text("General")
                Text("Utilities")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Sidebar", systemImage: "sidebar.left") {}
                        .labelStyle(.iconOnly)
                }
            }
        } content: {
            List {
                Text("Keystroke Overlay")
                Text("Capture & Mark")
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SettingsToolbarTitle(title: "Utilities")
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarSpacer(.flexible)
            }
        } detail: {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Label("Keystroke Overlay", systemImage: "keyboard.badge.eye")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
