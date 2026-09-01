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

        let expandedLayout = try await waitForSeparatorAlignment(in: window)

        model.visibility = .doubleColumn
        _ = try await waitForSeparatorAlignment(
            in: window,
            differingFrom: expandedLayout.dividerX
        )
    }

    /// Public toolbar APIs expose the tracking item but not its rendered frame, so this
    /// regression test compares the AppKit separator and split-divider views directly.
    private func waitForSeparatorAlignment(
        in window: NSWindow,
        differingFrom previousDividerX: CGFloat? = nil
    ) async throws -> SeparatorLayout {
        // SwiftUI can publish the split-view state across several AppKit layout passes,
        // especially while the rest of the test bundle is running in parallel.
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(10))
            window.contentView?.superview?.layoutSubtreeIfNeeded()

            if let layout = separatorLayout(in: window),
                layout.isAligned,
                previousDividerX.map({ abs(layout.dividerX - $0) > 0.5 }) ?? true
            {
                return layout
            }
        }

        let layout = try #require(separatorLayout(in: window))
        if let previousDividerX {
            #expect(abs(layout.dividerX - previousDividerX) > 0.5)
        }
        #expect(layout.isAligned)
        return layout
    }

    private func separatorLayout(in window: NSWindow) -> SeparatorLayout? {
        guard let themeFrame = window.contentView?.superview else { return nil }
        let descendants = descendants(of: themeFrame)
        let separators = descendants.filter {
            String(describing: type(of: $0)) == "NSSeparatorToolbarItemView"
        }
        let contentDividers = descendants.filter {
            String(describing: type(of: $0)) == "NSSplitDividerView"
                && $0.frame.width >= 4
        }
        guard let separator = separators.max(by: { separatorX(for: $0) < separatorX(for: $1) }),
            let contentDivider = contentDividers.max(
                by: { separatorX(for: $0) < separatorX(for: $1) }
            )
        else {
            return nil
        }

        let layout = SeparatorLayout(
            separatorX: separatorX(for: separator),
            dividerX: separatorX(for: contentDivider)
        )
        return layout.separatorX > 0 && layout.dividerX > 0 ? layout : nil
    }

    private func separatorX(for view: NSView) -> CGFloat {
        view.convert(view.bounds, to: nil).midX
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private struct SeparatorLayout {
    let separatorX: CGFloat
    let dividerX: CGFloat

    var isAligned: Bool {
        abs(separatorX - dividerX) <= 0.5
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
