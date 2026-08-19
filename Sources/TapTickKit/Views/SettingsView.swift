import AppKit
import SwiftUI

/// The main settings view with a sidebar for navigation across global and feature-specific areas.
public struct SettingsView: View {
    public init() {}

    @Environment(UtilitiesController.self) private var utilities
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(UpdateService.self) private var updateService

    enum Tab: String, Hashable, CaseIterable {
        case general = "General"
        case applications = "Applications"
        case scripts = "Scripts"
        case utilities = "Utilities"
        case about = "About"

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .applications: return "sparkles.rectangle.stack"
            case .scripts: return "terminal"
            case .utilities: return "wrench.and.screwdriver"
            case .about: return "info.circle"
            }
        }

        var iconPointSize: CGFloat {
            switch self {
            case .utilities:
                12
            case .general, .applications, .scripts, .about:
                14
            }
        }
    }

    @State private var selectedTab: Tab = .applications
    public var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                HStack(spacing: 12) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: tab.iconPointSize, weight: .regular))
                        .frame(width: 22)

                    Text(tab.rawValue)
                }
            }
            .frame(minWidth: 180, idealWidth: 180, maxWidth: 180)
            .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 180)
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
                    .environment(cloudSync)
            case .applications:
                ApplicationsView()
            case .scripts:
                ScriptsView()
            case .utilities:
                UtilitiesView()
                    .environment(utilities)
            case .about:
                AboutView()
                    .environment(updateService)
            }
        }
        .background(SettingsWindowTitleSync(title: selectedTab.rawValue))
    }
}

private struct SettingsWindowTitleSync: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}
