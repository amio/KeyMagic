import SwiftUI

/// Owns the persistent Settings window structure and its sidebar navigation.
public struct SettingsView: View {
    public init() {}

    @Environment(UtilitiesController.self) private var utilities
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(UpdateService.self) private var updateService

    enum SettingsSection: String, Hashable, CaseIterable, Identifiable {
        case general = "General"
        case applications = "Applications"
        case scripts = "Scripts"
        case menuBar = "Menu Bar"
        case utilities = "Utilities"
        case about = "About"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .applications: return "sparkles.rectangle.stack"
            case .scripts: return "terminal"
            case .menuBar: return "menubar.rectangle"
            case .utilities: return "wrench.and.screwdriver"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedSection: SettingsSection = .applications
    @FocusState private var isSidebarFocused: Bool

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            selectedPane
                .navigationTitle(selectedSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedSection) { _, section in
            restoreSidebarFocus(afterSelecting: section)
        }
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.systemImage)
        }
        .navigationSplitViewColumnWidth(
            min: 180,
            ideal: 210,
            max: 260
        )
        .listStyle(.sidebar)
        .focused($isSidebarFocused)
    }

    /// Replacing the detail can interrupt AppKit's first-responder handoff from the click.
    /// Restore it after the selection transaction so the sidebar keeps native list focus.
    private func restoreSidebarFocus(afterSelecting section: SettingsSection) {
        Task { @MainActor in
            await Task.yield()
            guard selectedSection == section, !isSidebarFocused else { return }
            isSidebarFocused = true
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
                .environment(cloudSync)
        case .applications:
            ApplicationsView()
        case .scripts:
            ScriptsView()
        case .menuBar:
            MenuBarTextSettingsView()
        case .utilities:
            UtilitiesView()
                .environment(utilities)
        case .about:
            AboutView()
                .environment(updateService)
        }
    }
}
