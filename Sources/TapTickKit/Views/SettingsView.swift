import SwiftUI

/// The main settings view with a sidebar for navigation across global and feature-specific areas.
public struct SettingsView: View {
    public init() {}

    @Environment(BuiltInFeatureController.self) private var builtInFeatures
    @Environment(LoginItemManager.self) private var loginItemManager
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(UpdateService.self) private var updateService

    enum Tab: String, Hashable, CaseIterable {
        case general = "General"
        case applications = "Applications"
        case scripts = "Scripts"
        case builtIns = "Built-Ins"

        var systemImage: String {
            switch self {
            case .general:      return "gearshape"
            case .applications: return "app.badge.checkmark"
            case .scripts:      return "terminal"
            case .builtIns:     return "sparkles.rectangle.stack"
            }
        }
    }

    @State private var selectedTab: Tab = .applications

    public var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
                    .environment(cloudSync)
                    .environment(updateService)
            case .applications:
                ApplicationsView()
            case .scripts:
                ScriptsView()
            case .builtIns:
                BuiltInFeaturesView()
                    .environment(builtInFeatures)
            }
        }
    }
}
