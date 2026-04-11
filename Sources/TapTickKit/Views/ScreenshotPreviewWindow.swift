import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Data Types

enum AnnotationMode: Sendable, CaseIterable {
    case freehand
    case rectangle

    var label: String {
        switch self {
        case .freehand: "Line"
        case .rectangle: "Rect"
        }
    }

    var systemImage: String {
        switch self {
        case .freehand: "pencil.tip"
        case .rectangle: "rectangle"
        }
    }
}

struct AnnotationPalette: Sendable {
    static let colors: [(name: String, color: NSColor)] = [
        ("Red", NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)),
        ("Orange", NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)),
        ("Yellow", NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)),
        ("Green", NSColor(red: 0.196, green: 0.843, blue: 0.294, alpha: 1.0)),
        ("Blue", NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)),
        ("White", NSColor.white),
    ]
}

struct Annotation {
    let mode: AnnotationMode
    /// Freehand: all sampled points. Rectangle: exactly [origin, corner].
    let points: [NSPoint]
    let color: NSColor
    let lineWidth: CGFloat
}

// MARK: - Shared Toolbar Model

@Observable
@MainActor
final class AnnotationToolbarModel {
    var currentMode: AnnotationMode = .freehand
    var colorIndex: Int = 0
    /// Callback fired by the Copy button in the toolbar.
    var onDone: (() -> Void)?

    var currentColor: NSColor {
        AnnotationPalette.colors[colorIndex].color
    }

    var currentColorName: String {
        AnnotationPalette.colors[colorIndex].name
    }

    var currentSwiftUIColor: Color {
        Color(nsColor: currentColor)
    }

    func toggleMode() {
        currentMode = currentMode == .freehand ? .rectangle : .freehand
    }

    func cycleColor() {
        colorIndex = (colorIndex + 1) % AnnotationPalette.colors.count
    }
}

// MARK: - Preview Window

private let canvasMargin: CGFloat = 16
/// Height of the standard system title bar.
private let titleBarHeight: CGFloat = 28
/// Corner radius of the window's blur background (continuous / squircle curve).
private let windowCornerRadius: CGFloat = 24
/// Standard close button center x ≈ 13pt; shift the cluster so it clears the corner tangent.
private let trafficLightShift: CGFloat = windowCornerRadius - 13   // = 13
/// Extra padding to push controls away from the window's top edge (accounts for large corner radius).
private let verticalPadding: CGFloat = 8
/// Toolbar leading inset: zoom trailing (59) + shift + gap (36).
private let toolbarLeadingInset: CGFloat = 59 + (windowCornerRadius - 13) + 36

/// NSHostingView subclass that refuses window-drag so toolbar buttons stay interactive.
private final class NonDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

@MainActor
final class ScreenshotPreviewWindow: NSPanel {
    var onDismiss: (() -> Void)?
    private let canvasView: AnnotationCanvasView
    private let toolbarModel = AnnotationToolbarModel()
    /// Retained so it can be shifted alongside the traffic lights in show().
    private var toolbarHostingView: NSView?

    init(image: NSImage) {
        let screenFrame = NSScreen.screenWithMouse?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero

        let chromeHeight = titleBarHeight + canvasMargin * 2
        let chromeWidth = canvasMargin * 2
        let maxImageWidth = screenFrame.width * 0.8 - chromeWidth
        let maxImageHeight = screenFrame.height * 0.8 - chromeHeight

        let imageSize = image.size
        let scale = min(1.0, min(maxImageWidth / imageSize.width, maxImageHeight / imageSize.height))
        let displaySize = NSSize(
            width: (imageSize.width * scale).rounded(),
            height: (imageSize.height * scale).rounded()
        )

        let windowWidth = displaySize.width + chromeWidth
        let windowHeight = displaySize.height + chromeHeight

        let contentRect = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        canvasView = AnnotationCanvasView(
            image: image,
            toolbarModel: toolbarModel,
            frame: NSRect(origin: .zero, size: displaySize)
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Screenshot"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear

        toolbarModel.onDone = { [weak self] in
            self?.commitAndClose()
        }

        installTitlebarAccessory()
        buildContentHierarchy(displaySize: displaySize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        adaptTitlebarControls()
    }

    /// Shifts traffic lights and toolbar away from the large rounded corner after AppKit layout.
    private func adaptTitlebarControls() {
        guard let titlebarView = standardWindowButton(.closeButton)?.superview else { return }
        // isFlipped: Y increases downward → positive delta moves away from top.
        // !isFlipped: Y increases upward  → negative delta moves away from top.
        let yDelta = verticalPadding * (titlebarView.isFlipped ? 1 : -1)

        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let btn = standardWindowButton(type) else { continue }
            btn.frame.origin.x += trafficLightShift
            btn.frame.origin.y += yDelta
        }
        toolbarHostingView?.frame.origin.y += yDelta
    }

    override func close() {
        onDismiss?()
        super.close()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch keyCode {
        case kVK_Tab where flags.contains(.option):
            toolbarModel.cycleColor()
            canvasView.needsDisplay = true

        case kVK_Tab:
            toolbarModel.toggleMode()
            canvasView.needsDisplay = true

        case kVK_Return:
            commitAndClose()

        case kVK_Escape:
            close()

        case kVK_ANSI_Z where flags.contains(.command):
            canvasView.undoLastAnnotation()

        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Private

    private func commitAndClose() {
        canvasView.copyToClipboard()
        close()
    }

    private func installTitlebarAccessory() {
        guard let closeButton = standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview
        else { return }

        let toolbarView = AnnotationToolbar(model: toolbarModel)
        let hostingView = NonDraggableHostingView(rootView: toolbarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        titlebarView.addSubview(hostingView)
        toolbarHostingView = hostingView

        NSLayoutConstraint.activate([
            // Fixed inset from the titlebar's left edge — pre-accounts for the traffic light
            // shift applied in show(), keeping the gap independent of AppKit re-layouts.
            hostingView.leadingAnchor.constraint(
                equalTo: titlebarView.leadingAnchor, constant: toolbarLeadingInset
            ),
            hostingView.trailingAnchor.constraint(
                equalTo: titlebarView.trailingAnchor, constant: -16
            ),
            hostingView.centerYAnchor.constraint(
                equalTo: closeButton.centerYAnchor
            ),
        ])
    }

    private func buildContentHierarchy(displaySize: NSSize) {
        guard let rootView = contentView else { return }

        // Clip the window shape here so NSVisualEffectView's internal blending
        // machinery is never disturbed by external layer surgery.
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = windowCornerRadius
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true

        // 1. Blurred background filling the entire window behind the title bar.
        let blur = NSVisualEffectView()
        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(blur, positioned: .below, relativeTo: nil)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: rootView.topAnchor),
            blur.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        // 2. Canvas view centered in the space below title bar with a drop shadow.
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.wantsLayer = true
        canvasView.layer?.cornerRadius = 12
        canvasView.layer?.cornerCurve = .continuous
        canvasView.layer?.masksToBounds = true

        // Shadow container — wrapper needed because masksToBounds clips the shadow.
        let shadowContainer = NSView()
        shadowContainer.translatesAutoresizingMaskIntoConstraints = false
        shadowContainer.wantsLayer = true
        shadowContainer.shadow = NSShadow()
        shadowContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        shadowContainer.layer?.shadowOpacity = 1
        shadowContainer.layer?.shadowRadius = 12
        shadowContainer.layer?.shadowOffset = CGSize(width: 0, height: -4)
        rootView.addSubview(shadowContainer)
        shadowContainer.addSubview(canvasView)

        NSLayoutConstraint.activate([
            shadowContainer.topAnchor.constraint(
                equalTo: rootView.safeAreaLayoutGuide.topAnchor,
                constant: canvasMargin
            ),
            shadowContainer.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            shadowContainer.bottomAnchor.constraint(
                equalTo: rootView.bottomAnchor,
                constant: -canvasMargin
            ),

            canvasView.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),

            canvasView.widthAnchor.constraint(equalToConstant: displaySize.width),
            canvasView.heightAnchor.constraint(equalToConstant: displaySize.height),
        ])
    }
}

// MARK: - Annotation Canvas

@MainActor
final class AnnotationCanvasView: NSView {
    private let toolbarModel: AnnotationToolbarModel
    private let image: NSImage
    private var annotations: [Annotation] = []
    private var currentPoints: [NSPoint] = []
    private var isDrawing = false
    private let lineWidth: CGFloat = 3.0

    init(image: NSImage, toolbarModel: AnnotationToolbarModel, frame: NSRect) {
        self.image = image
        self.toolbarModel = toolbarModel
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Actions

    func undoLastAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
    }

    func copyToClipboard() {
        let composited = NSImage(size: image.size)
        composited.lockFocus()

        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        let scaleX = image.size.width / bounds.width
        let scaleY = image.size.height / bounds.height

        for annotation in annotations {
            drawAnnotation(annotation, scaleX: scaleX, scaleY: scaleY)
        }

        composited.unlockFocus()

        guard let tiffData = composited.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

        for annotation in annotations {
            drawAnnotation(annotation, scaleX: 1.0, scaleY: 1.0)
        }

        if isDrawing, currentPoints.count >= 2 {
            let preview = Annotation(
                mode: toolbarModel.currentMode,
                points: currentPoints,
                color: toolbarModel.currentColor,
                lineWidth: lineWidth
            )
            drawAnnotation(preview, scaleX: 1.0, scaleY: 1.0)
        }
    }

    private func drawAnnotation(
        _ annotation: Annotation,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        let scaledPoints = annotation.points.map { pt in
            NSPoint(x: pt.x * scaleX, y: pt.y * scaleY)
        }
        let scaledWidth = annotation.lineWidth * max(scaleX, scaleY)

        guard scaledPoints.count >= 2 else { return }

        annotation.color.setStroke()

        switch annotation.mode {
        case .freehand:
            let path = NSBezierPath()
            path.lineWidth = scaledWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: scaledPoints[0])
            for point in scaledPoints.dropFirst() {
                path.line(to: point)
            }
            path.stroke()

        case .rectangle:
            let start = scaledPoints[0]
            let end = scaledPoints[scaledPoints.count - 1]
            let rect = NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            let path = NSBezierPath(rect: rect)
            path.lineWidth = scaledWidth
            path.stroke()
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }

        isDrawing = true
        currentPoints = [point]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentPoints.append(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        isDrawing = false

        guard currentPoints.count >= 2 else {
            currentPoints.removeAll()
            needsDisplay = true
            return
        }

        let first = currentPoints[0]
        let last = currentPoints[currentPoints.count - 1]
        let dx = last.x - first.x
        let dy = last.y - first.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance > 3 {
            annotations.append(Annotation(
                mode: toolbarModel.currentMode,
                points: currentPoints,
                color: toolbarModel.currentColor,
                lineWidth: lineWidth
            ))
        }

        currentPoints.removeAll()
        needsDisplay = true
    }
}

// MARK: - Title Bar Toolbar (SwiftUI)

private struct AnnotationToolbar: View {
    @Bindable var model: AnnotationToolbarModel

    var body: some View {
        HStack {
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    modeSwitch
                    keycap("TAB")
                }
                HStack(spacing: 6) {
                    colorIndicator
                    keycap("⌥ TAB")
                }
            }

            Spacer()

            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    copyButton
                    keycap("↩")
                }
            }
        }
    }

    // MARK: - Mode Switch (Segmented)

    private var modeSwitch: some View {
        HStack(spacing: 1) {
            ForEach(AnnotationMode.allCases, id: \.label) { mode in
                modeSegment(mode)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 5.5)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func modeSegment(_ mode: AnnotationMode) -> some View {
        let isActive = model.currentMode == mode
        return Image(systemName: mode.systemImage)
            .font(.system(size: 11, weight: isActive ? .medium : .regular))
            .foregroundStyle(isActive ? .primary : .tertiary)
            .frame(width: 26, height: 18)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.currentMode = mode }
    }

    // MARK: - Color Indicator

    private var colorIndicator: some View {
        Circle()
            .fill(model.currentSwiftUIColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .contentShape(Circle())
            .onTapGesture { model.cycleColor() }
    }

    // MARK: - Keycap Badge

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }

    // MARK: - Copy Button

    private var copyButton: some View {
        Text("Copy")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onTapGesture { model.onDone?() }
    }
}

// MARK: - NSScreen Helper

private extension NSScreen {
    /// Returns the screen that contains the current mouse cursor location.
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}
