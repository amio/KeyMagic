import AppKit
import SwiftUI

/// Product-facing settings pane for app identity, release metadata, and update controls.
struct AboutView: View {
    @Environment(UpdateService.self) private var updateService

    private let runtimeConfiguration = TapTickRuntimeConfiguration.current
    private let socialURL = URL(string: "https://x.com/amiojinn")!
    private let websiteURL = URL(string: "https://amio.cn")!
    private let linkAccent = Color(red: 0.47, green: 0.71, blue: 1.0)

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                brandBlock
                footerLinks
                updatesSection
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .padding(.top, 12)
        }
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.33, green: 0.54, blue: 0.95).opacity(0.04))
                    .frame(width: 320, height: 320)
                    .blur(radius: 40)
                    .offset(y: 8)

                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 176, height: 176)
                    .blur(radius: 22)
                    .offset(y: -12)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 18)
            }
            .frame(width: 222, height: 190)

            VStack(spacing: 6) {
                Text(runtimeConfiguration.displayName)
                    .font(.system(size: 40, weight: .semibold))

                Text("Version \(runtimeConfiguration.versionLabel)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var updatesSection: some View {
        VStack(spacing: 0) {
            Text("Updates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: updatesWidth, alignment: .leading)
                .padding(.bottom, 6)
                .padding(.top, 32)

            updateRow(
                title: "Automatically check for updates",
                detail: updateService.automaticallyChecksForUpdates ? "Enabled" : "Disabled"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { updateService.automaticallyChecksForUpdates },
                        set: { updateService.automaticallyChecksForUpdates = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()
                .frame(maxWidth: updatesWidth)

            updateRow(
                title: "Last checked",
                detail: lastCheckedSummary
            ) {
                Button {
                    updateService.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(updateService.canCheckForUpdates ? Color.accentColor : Color.secondary)
                .disabled(!updateService.canCheckForUpdates)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footerLinks: some View {
        Text(
            .init(
                "made by [@amiojinn](" + socialURL.absoluteString + ")  visit [amio.cn](" + websiteURL.absoluteString
                    + ")"
            )
        )
        .tint(linkAccent)
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func updateRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            accessory()
        }
        .frame(maxWidth: updatesWidth)
        .padding(.vertical, 10)
    }
}

private extension AboutView {
    var updatesWidth: CGFloat {
        620
    }

    var lastCheckedSummary: String {
        guard let lastCheck = updateService.lastUpdateCheckDate else {
            return "Never"
        }

        return lastCheck.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}
