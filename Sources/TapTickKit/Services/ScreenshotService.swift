import AppKit
import Foundation

/// Orchestrates screenshot capture using macOS's native `screencapture` tool.
@MainActor
final class ScreenshotService {
    private var previewWindow: ScreenshotPreviewWindow?

    var lastAnnotationMode: AnnotationMode = .freehand
    var lastAnnotationColorIndex: Int = 0

    /// Called whenever the user changes draw mode or color in the annotation window.
    var onAnnotationSettingsChanged: ((AnnotationMode, Int) -> Void)?

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
        previewWindow?.close()

        let window = ScreenshotPreviewWindow(
            image: image,
            initialMode: lastAnnotationMode,
            initialColorIndex: lastAnnotationColorIndex
        )
        previewWindow = window

        window.onAnnotationSettingsChanged = { [weak self] mode, colorIndex in
            guard let self else { return }
            lastAnnotationMode = mode
            lastAnnotationColorIndex = colorIndex
            onAnnotationSettingsChanged?(mode, colorIndex)
        }

        window.onDismiss = { [weak self] in
            self?.previewWindow = nil
        }
        window.show()
    }
}