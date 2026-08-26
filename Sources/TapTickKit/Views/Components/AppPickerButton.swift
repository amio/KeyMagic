import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A button that opens an app picker (file dialog filtered to .app bundles).
struct AppPickerButton: View {
    @Binding var selectedBundleID: String
    @Binding var selectedAppName: String

    @State private var isShowingPicker = false
    @State private var pickerError = ""
    @State private var isShowingPickerError = false

    var body: some View {
        HStack(spacing: 10) {
            if !selectedBundleID.isEmpty {
                AppIconView(bundleIdentifier: selectedBundleID)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedAppName)
                        .fontWeight(.medium)
                    Text(selectedBundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Choose App…") {
                isShowingPicker = true
            }
        }
        .fileImporter(
            isPresented: $isShowingPicker,
            allowedContentTypes: [.applicationBundle]
        ) { result in
            selectApp(from: result)
        }
        .alert("Unable to Choose App", isPresented: $isShowingPickerError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pickerError)
        }
    }

    private func selectApp(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                throw AppPickerError.missingBundleIdentifier
            }

            selectedBundleID = bundleID
            selectedAppName = url.deletingPathExtension().lastPathComponent
        } catch {
            pickerError = error.localizedDescription
            isShowingPickerError = true
        }
    }
}

private enum AppPickerError: LocalizedError {
    case missingBundleIdentifier

    var errorDescription: String? {
        "The selected item is not an application with a bundle identifier."
    }
}

/// Displays an app icon from a bundle identifier.
struct AppIconView: View {
    let bundleIdentifier: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage?
        {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
