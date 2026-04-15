import AppKit
import SwiftUI

/// Displays script output as a subtitle-style floating overlay near the bottom-center of the screen.
@MainActor
public final class ScriptOutputPresenter {
    public init() {}
    private let model = ScriptOutputPresentationModel()
    private lazy var hostingView = NSHostingView(rootView: ScriptOutputSubtitleView(model: model))
    private lazy var panel: NSPanel = makePanel()
    private var hideTask: Task<Void, Never>?
    private var isShowing = false

    /// How long the subtitle stays fully visible before fading out.
    private let holdDuration: TimeInterval = 4
    /// Duration of the fade-out animation.
    private let fadeOutDuration: TimeInterval = 0.4

    public func show(text: String, isError: Bool) {
        let display = Self.formatForSubtitle(text)
        guard !display.isEmpty else { return }

        hideTask?.cancel()
        model.text = display
        model.isError = isError

        if isShowing {
            panel.alphaValue = 1
            layoutPanel()
        } else {
            isShowing = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            layoutPanel()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }

        scheduleHide()
    }

    // MARK: - Panel Lifecycle

    private func scheduleHide() {
        hideTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = self.fadeOutDuration
                self.panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }

            self.isShowing = false
            self.panel.orderOut(nil)
        }
    }

    private func layoutPanel() {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        panel.setContentSize(size)

        guard let screen = targetScreen() else { return }

        let frame = screen.visibleFrame
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.15
        )
        panel.setFrameOrigin(origin)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
            .transient,
        ]

        return panel
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }

    // MARK: - Text Formatting

    /// Keep only the last few non-empty lines, capped by character count.
    static func formatForSubtitle(_ text: String, maxLines: Int = 3, maxLength: Int = 200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let tail = Array(lines.suffix(maxLines))
        var result = tail.joined(separator: "\n")

        if result.count > maxLength {
            result = "…" + String(result.suffix(maxLength - 1))
        }

        return result
    }
}

// MARK: - Presentation Model

@Observable
@MainActor
private final class ScriptOutputPresentationModel {
    var text = ""
    var isError = false
}

// MARK: - Subtitle View

private struct ScriptOutputSubtitleView: View {
    @Bindable var model: ScriptOutputPresentationModel

    var body: some View {
        Text(model.text)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.isError ? Color.red.opacity(0.7) : Color.black.opacity(0.72))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 600)
            .padding(20)
    }
}