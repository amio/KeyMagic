import SwiftUI

/// Owns the persistent Settings window structure and its sidebar navigation.
public struct SettingsView: View {
    public init() {}

    @Environment(UtilitiesController.self) private var utilities
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(UpdateService.self) private var updateService

    enum Tab: String, Hashable, CaseIterable {
        case general = "General"
        case applications = "Applications"
        case scripts = "Scripts"
        case menuBar = "Menu Bar"
        case utilities = "Utilities"
        case about = "About"

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

        var iconPointSize: CGFloat {
            switch self {
            case .utilities:
                12
            case .general, .applications, .scripts, .menuBar, .about:
                14
            }
        }
    }

    @State private var selectedTab: Tab = .applications

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            selectedPane
                .navigationTitle(selectedTab.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }

    private var sidebar: some View {
        List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
            HStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: tab.iconPointSize, weight: .regular))
                    .frame(width: 22)

                Text(tab.rawValue)
            }
        }
        .navigationSplitViewColumnWidth(
            min: Self.sidebarWidth,
            ideal: Self.sidebarWidth,
            max: Self.sidebarWidth
        )
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedTab {
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

    private static let sidebarWidth: CGFloat = 180
}
