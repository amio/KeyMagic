import AppKit
import Foundation

/// Orchestrates screenshot capture using macOS's native `screencapture` tool.
@MainActor
final class ScreenshotService {
    private var previewWindow: ScreenshotPreviewWindow?

    /// Interactive capture → clipboard (no preview UI).
    func captureToClipboard() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-ic"]
        task.terminationHandler = { _ in }
        try? task.run()
    }

    /// Interactive capture → temp file → annotation preview window.
    func captureAndMark() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("taptick_screenshot_\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", tempURL.path]

        // Run screencapture asynchronously to avoid blocking the main thread
        task.terminationHandler = { [weak self, tempURL] _ in
            Task { @MainActor [weak self] in
                self?.handleCaptureCompletion(tempURL: tempURL)
            }
        }
        try? task.run()
    }

    private func handleCaptureCompletion(tempURL: URL) {
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard FileManager.default.fileExists(atPath: tempURL.path),
              let image = NSImage(contentsOf: tempURL)
        else {
            // User cancelled the capture
            return
        }

        showPreviewWindow(image: image)
    }

    private func showPreviewWindow(image: NSImage) {
        // Close any existing preview window
        previewWindow?.close()

        let window = ScreenshotPreviewWindow(image: image)
        previewWindow = window
        window.onDismiss = { [weak self] in
            self?.previewWindow = nil
        }
        window.show()
    }
}