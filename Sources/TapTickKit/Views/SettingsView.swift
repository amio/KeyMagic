import SwiftUI

/// Owns the persistent Settings window structure and its sidebar navigation.
public struct SettingsView: View {
    public init() {}

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
    @State private var selectedScriptID: UUID?
    @State private var scriptNameSelectionRequestID: UUID?
    @State private var selectedUtilityID: UtilityID = .keystrokeOverlay
    @FocusState private var isSidebarFocused: Bool

    public var body: some View {
        // macOS always keeps the content column of a three-column split view visible,
        // so sections with their own directory use three columns.
        Group {
            if selectedSection == .scripts {
                scriptsNavigation
            } else if selectedSection == .utilities {
                utilitiesNavigation
            } else {
                standardNavigation
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedSection) { _, section in
            restoreSidebarFocus(afterSelecting: section)
        }
    }

    private var scriptsNavigation: some View {
        NavigationSplitView {
            sidebar
        } content: {
            ScriptsDirectoryView(
                selection: $selectedScriptID,
                nameSelectionRequestID: $scriptNameSelectionRequestID
            )
            .navigationTitle(SettingsSection.scripts.rawValue)
            .navigationSplitViewColumnWidth(
                min: 250,
                ideal: 280,
                max: 340
            )
        } detail: {
            ScriptDetailView(
                selection: $selectedScriptID,
                nameSelectionRequestID: $scriptNameSelectionRequestID
            )
        }
    }

    private var standardNavigation: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            selectedPane
                .navigationTitle(selectedSection.rawValue)
        }
    }

    private var utilitiesNavigation: some View {
        NavigationSplitView {
            sidebar
        } content: {
            UtilitiesDirectoryView(selection: $selectedUtilityID)
                .navigationTitle(SettingsSection.utilities.rawValue)
                .navigationSplitViewColumnWidth(
                    min: 250,
                    ideal: 280,
                    max: 340
                )
        } detail: {
            UtilityDetailView(selectedFeatureID: selectedUtilityID)
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
            EmptyView()
        case .menuBar:
            MenuBarTextSettingsView()
        case .utilities:
            EmptyView()
        case .about:
            AboutView()
                .environment(updateService)
        }
    }
}
