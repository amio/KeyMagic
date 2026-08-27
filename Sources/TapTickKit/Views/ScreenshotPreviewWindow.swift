import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Data Types

enum AnnotationMode: String, Sendable, CaseIterable, Codable, Hashable {
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
        case .freehand: "scribble"
        case .rectangle: "rectangle"
        }
    }

    var toggled: AnnotationMode {
        switch self {
        case .freehand: .rectangle
        case .rectangle: .freehand
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
    private(set) var selectedMode: AnnotationMode
    private var temporaryModeOverride: AnnotationMode?
    var colorIndex: Int
    /// Callback fired by the Copy button in the toolbar.
    var onDone: (() -> Void)?
    /// Fired whenever the user changes draw mode or color, so callers can persist the selection.
    var onSettingsChanged: ((AnnotationMode, Int) -> Void)?

    init(mode: AnnotationMode = .freehand, colorIndex: Int = 0) {
        self.selectedMode = mode
        self.colorIndex = colorIndex
    }

    var currentMode: AnnotationMode {
        temporaryModeOverride ?? selectedMode
    }

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
        setSelectedMode(selectedMode.toggled)
    }

    func setSelectedMode(_ mode: AnnotationMode) {
        guard selectedMode != mode else { return }
        selectedMode = mode
        onSettingsChanged?(selectedMode, colorIndex)
    }

    func cycleColor() {
        colorIndex = (colorIndex + 1) % AnnotationPalette.colors.count
        onSettingsChanged?(selectedMode, colorIndex)
    }

    func setTemporaryModeSwitchActive(_ isActive: Bool) {
        temporaryModeOverride = isActive ? selectedMode.toggled : nil
    }
}

// MARK: - Preview Window

private let canvasMargin: CGFloat = 16
/// Height of the unified compact header installed by `configureHeader()`.
private let headerHeight: CGFloat = 40
/// Keeps tiny captures usable without coupling the window width to toolbar copy or font metrics.
private let minimumCanvasHeight: CGFloat = 160
private let minimumHeaderBreathingRoom: CGFloat = 32

/// NSHostingView subclass that refuses window-drag so toolbar buttons stay interactive.
private final class NonDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

@MainActor
final class ScreenshotPreviewWindow: NSPanel {
    var onDismiss: (() -> Void)?
    var onAnnotationSettingsChanged: ((AnnotationMode, Int) -> Void)?
    private let canvasView: AnnotationCanvasView
    private let toolbarModel: AnnotationToolbarModel
    private var isOptionPressed = false
    private var didUseOptionPressAsModifier = false
    private var didActivateTemporaryModeSwitch = false
    private var optionHoldActivationTask: Task<Void, Never>?
    private let optionHoldThreshold: Duration = .milliseconds(220)

    init(image: NSImage, initialMode: AnnotationMode = .freehand, initialColorIndex: Int = 0) {
        let screenFrame =
            NSScreen.screenWithMouse?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero

        let chromeHeight = headerHeight + canvasMargin * 2
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

        let toolbarModel = AnnotationToolbarModel(mode: initialMode, colorIndex: initialColorIndex)
        canvasView = AnnotationCanvasView(
            image: image,
            toolbarModel: toolbarModel,
            frame: NSRect(origin: .zero, size: displaySize)
        )
        self.toolbarModel = toolbarModel

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Screenshot content can contain any luminance. A stable dark chrome gives the system
        // materials and controls enough contrast without changing the captured image itself.
        appearance = NSAppearance(named: .darkAqua)
        title = "Screenshot"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        configureHeader()

        toolbarModel.onDone = { [weak self] in
            self?.commitAndClose()
        }
        toolbarModel.onSettingsChanged = { [weak self] mode, colorIndex in
            self?.onAnnotationSettingsChanged?(mode, colorIndex)
        }

        installTitlebarAccessories()
        buildContentHierarchy(displaySize: displaySize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        resetOptionModeInteraction()
        onDismiss?()
        super.close()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isOptionPressed {
            didUseOptionPressAsModifier = true
        }

        switch keyCode {
        case kVK_Tab:
            toolbarModel.cycleColor()
            canvasView.needsDisplay = true

        case kVK_Return, kVK_ANSI_KeypadEnter:
            commitAndClose()

        case kVK_Escape:
            close()

        case kVK_ANSI_Z where flags.contains(.command):
            canvasView.undoLastAnnotation()

        default:
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isOptionActive = flags.contains(.option)

        if isOptionActive == isOptionPressed {
            return
        }

        if isOptionActive {
            beginOptionModeInteraction()
        } else {
            endOptionModeInteraction()
        }
    }

    override func resignKey() {
        resetOptionModeInteraction()
        super.resignKey()
    }

    // MARK: - Private

    private func commitAndClose() {
        canvasView.copyToClipboard()
        close()
    }

    private func beginOptionModeInteraction() {
        isOptionPressed = true
        didUseOptionPressAsModifier = false
        didActivateTemporaryModeSwitch = false

        let threshold = optionHoldThreshold
        optionHoldActivationTask?.cancel()
        optionHoldActivationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: threshold)
            } catch {
                return
            }

            guard let self, self.isOptionPressed else { return }
            self.didActivateTemporaryModeSwitch = true
            self.toolbarModel.setTemporaryModeSwitchActive(true)
            self.canvasView.needsDisplay = true
        }
    }

    private func endOptionModeInteraction() {
        optionHoldActivationTask?.cancel()
        optionHoldActivationTask = nil

        if didActivateTemporaryModeSwitch {
            toolbarModel.setTemporaryModeSwitchActive(false)
            canvasView.needsDisplay = true
        } else if !didUseOptionPressAsModifier {
            toolbarModel.toggleMode()
            canvasView.needsDisplay = true
        }

        isOptionPressed = false
        didUseOptionPressAsModifier = false
        didActivateTemporaryModeSwitch = false
    }

    private func resetOptionModeInteraction() {
        optionHoldActivationTask?.cancel()
        optionHoldActivationTask = nil
        toolbarModel.setTemporaryModeSwitchActive(false)
        isOptionPressed = false
        didUseOptionPressAsModifier = false
        didActivateTemporaryModeSwitch = false
        canvasView.needsDisplay = true
    }

    private func configureHeader() {
        let toolbar = NSToolbar(identifier: "ScreenshotPreview.Header")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
        toolbarStyle = .unifiedCompact
        titlebarSeparatorStyle = .none
    }

    private func installTitlebarAccessories() {
        let toolsWidth = addTitlebarAccessory(
            AnnotationToolbar(model: toolbarModel, section: .tools),
            at: .left
        )
        let completionWidth = addTitlebarAccessory(
            AnnotationToolbar(model: toolbarModel, section: .completion),
            at: .right
        )
        enforceMinimumWindowSize(
            toolsWidth: toolsWidth,
            completionWidth: completionWidth
        )
    }

    private func addTitlebarAccessory<Content: View>(
        _ content: Content,
        at layoutAttribute: NSLayoutConstraint.Attribute
    ) -> CGFloat {
        let hostingView = NonDraggableHostingView(rootView: content)
        hostingView.sizingOptions = .intrinsicContentSize
        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = fittingSize

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = layoutAttribute
        accessory.view = hostingView
        addTitlebarAccessoryViewController(accessory)
        return fittingSize.width
    }

    private func enforceMinimumWindowSize(toolsWidth: CGFloat, completionWidth: CGFloat) {
        let titlebarView = standardWindowButton(.closeButton)?.superview
        titlebarView?.layoutSubtreeIfNeeded()

        let trafficLightTrailingEdge =
            [
                NSWindow.ButtonType.closeButton,
                .miniaturizeButton,
                .zoomButton,
            ]
            .compactMap { standardWindowButton($0) }
            .map { $0.convert($0.bounds, to: nil).maxX }
            .max() ?? 0

        let minimumFrameSize = NSSize(
            width: ceil(
                trafficLightTrailingEdge + toolsWidth + completionWidth
                    + minimumHeaderBreathingRoom
            ),
            height: headerHeight + canvasMargin * 2 + minimumCanvasHeight
        )
        minSize = minimumFrameSize
        let effectiveMinimumFrameSize = minSize

        let targetSize = NSSize(
            width: max(frame.width, effectiveMinimumFrameSize.width),
            height: max(frame.height, effectiveMinimumFrameSize.height)
        )
        guard targetSize != frame.size else { return }

        setFrame(
            NSRect(
                x: frame.midX - targetSize.width / 2,
                y: frame.midY - targetSize.height / 2,
                width: targetSize.width,
                height: targetSize.height
            ),
            display: false
        )
    }

    private func buildContentHierarchy(displaySize: NSSize) {
        guard let rootView = contentView else { return }

        // Match the system preview panel: a HUD material owns the blur, tint, and accessibility
        // adaptation while AppKit keeps the native window shape.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
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

        // Canvas view centered in the space below title bar with a drop shadow.
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
                greaterThanOrEqualTo: rootView.safeAreaLayoutGuide.topAnchor,
                constant: canvasMargin
            ),
            shadowContainer.centerYAnchor.constraint(
                equalTo: rootView.safeAreaLayoutGuide.centerYAnchor
            ),
            shadowContainer.bottomAnchor.constraint(
                lessThanOrEqualTo: rootView.bottomAnchor,
                constant: -canvasMargin
            ),
            shadowContainer.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),

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
    private var currentStrokeMode: AnnotationMode?
    private var isDrawing = false
    private let lineWidth: CGFloat = 3.0
    private let minimumPointSpacing: CGFloat = 1.5
    private let freehandSmoothingPasses = 2
    private let freehandNeighborWeight: CGFloat = 0.2

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
            let pngData = bitmapRep.representation(using: .png, properties: [:])
        else { return }

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
                mode: currentStrokeMode ?? toolbarModel.currentMode,
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
            let path = freehandPath(for: scaledPoints, lineWidth: scaledWidth)
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

    private func freehandPath(for points: [NSPoint], lineWidth: CGFloat) -> NSBezierPath {
        let smoothedPoints = smoothedFreehandPoints(points)
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        guard let first = smoothedPoints.first else { return path }
        path.move(to: first)

        guard smoothedPoints.count > 1 else { return path }
        guard smoothedPoints.count > 2 else {
            path.line(to: smoothedPoints[1])
            return path
        }

        for index in 0..<(smoothedPoints.count - 1) {
            let previous = index > 0 ? smoothedPoints[index - 1] : smoothedPoints[index]
            let current = smoothedPoints[index]
            let next = smoothedPoints[index + 1]
            let nextNext = index + 2 < smoothedPoints.count ? smoothedPoints[index + 2] : next

            let controlPoint1 = NSPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let controlPoint2 = NSPoint(
                x: next.x - (nextNext.x - current.x) / 6,
                y: next.y - (nextNext.y - current.y) / 6
            )

            path.curve(to: next, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
        }

        return path
    }

    private func smoothedFreehandPoints(_ points: [NSPoint]) -> [NSPoint] {
        guard points.count > 2 else { return points }

        var smoothedPoints = points

        for _ in 0..<freehandSmoothingPasses {
            smoothedPoints = smoothPointPass(smoothedPoints)
        }

        return smoothedPoints
    }

    private func smoothPointPass(_ points: [NSPoint]) -> [NSPoint] {
        guard points.count > 2 else { return points }

        let centerWeight = 1 - (freehandNeighborWeight * 2)
        var smoothedPoints = [points[0]]
        smoothedPoints.reserveCapacity(points.count)

        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]

            smoothedPoints.append(
                NSPoint(
                    x: previous.x * freehandNeighborWeight
                        + current.x * centerWeight
                        + next.x * freehandNeighborWeight,
                    y: previous.y * freehandNeighborWeight
                        + current.y * centerWeight
                        + next.y * freehandNeighborWeight
                ))
        }

        smoothedPoints.append(points[points.count - 1])
        return smoothedPoints
    }

    private func appendCurrentPoint(_ point: NSPoint) {
        guard let lastPoint = currentPoints.last else {
            currentPoints.append(point)
            return
        }

        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        let distanceSquared = dx * dx + dy * dy
        let minimumSpacingSquared = minimumPointSpacing * minimumPointSpacing

        guard distanceSquared >= minimumSpacingSquared else { return }
        currentPoints.append(point)
    }

    private func shouldCommitCurrentAnnotation() -> Bool {
        switch currentStrokeMode ?? toolbarModel.currentMode {
        case .freehand:
            return strokeLength(for: currentPoints) > 3
        case .rectangle:
            guard let first = currentPoints.first,
                let last = currentPoints.last
            else { return false }
            let dx = last.x - first.x
            let dy = last.y - first.y
            return sqrt(dx * dx + dy * dy) > 3
        }
    }

    private func strokeLength(for points: [NSPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }

        var length: CGFloat = 0

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let dx = current.x - previous.x
            let dy = current.y - previous.y
            length += sqrt(dx * dx + dy * dy)
        }

        return length
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }

        isDrawing = true
        currentStrokeMode = toolbarModel.currentMode
        currentPoints = [point]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        let point = convert(event.locationInWindow, from: nil)
        appendCurrentPoint(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        isDrawing = false

        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            appendCurrentPoint(point)
        }

        guard currentPoints.count >= 2 else {
            currentStrokeMode = nil
            currentPoints.removeAll()
            needsDisplay = true
            return
        }

        if shouldCommitCurrentAnnotation() {
            annotations.append(
                Annotation(
                    mode: currentStrokeMode ?? toolbarModel.currentMode,
                    points: currentPoints,
                    color: toolbarModel.currentColor,
                    lineWidth: lineWidth
                ))
        }

        currentStrokeMode = nil
        currentPoints.removeAll()
        needsDisplay = true
    }
}

// MARK: - Title Bar Toolbar (SwiftUI)

private enum AnnotationToolbarSection {
    case tools
    case completion
}

private struct AnnotationToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 20)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
            }
            .contentShape(.rect(cornerRadius: 6))
    }
}

private struct AnnotationToolbar: View {
    @Bindable var model: AnnotationToolbarModel
    let section: AnnotationToolbarSection

    var body: some View {
        Group {
            switch section {
            case .tools:
                toolControls
            case .completion:
                copyControl
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var toolControls: some View {
        HStack(spacing: 16) {
            modeControl
            colorControl
        }
    }

    private var accessibilityLabel: String {
        switch section {
        case .tools:
            "Annotation controls"
        case .completion:
            "Screenshot actions"
        }
    }

    // MARK: - Controls

    private var modeControl: some View {
        HStack(spacing: 6) {
            Picker("Annotation Tool", selection: modeSelection) {
                ForEach(AnnotationMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.systemImage)
                        .labelStyle(.iconOnly)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Annotation Tool")
            .accessibilityValue(model.currentMode.label)
            .accessibilityHint(
                "Tap Option to switch tools. Hold Option to temporarily use the other tool."
            )

            keycap("OPT")
        }
        .help(
            "Choose line or rectangle · Tap Option to switch; hold Option to temporarily use the other tool"
        )
    }

    private var colorControl: some View {
        HStack(spacing: 6) {
            Button {
                model.cycleColor()
            } label: {
                Circle()
                    .fill(model.currentSwiftUIColor)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                    }
            }
            .buttonStyle(AnnotationToolbarIconButtonStyle())
            .accessibilityLabel("Annotation Color")
            .accessibilityValue(model.currentColorName)
            .accessibilityHint("Press Tab to select the next annotation color.")

            keycap("TAB")
        }
        .help("Cycle annotation color · Press Tab to select the next color")
    }

    private var copyControl: some View {
        Button("Copy") {
            model.onDone?()
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityHint(
            "Copies the annotated image and closes the preview. Press Enter to activate."
        )
        .help("Copy and close · Press Enter")
    }

    private var modeSelection: Binding<AnnotationMode> {
        Binding(
            get: { model.currentMode },
            set: { model.setSelectedMode($0) }
        )
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
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
