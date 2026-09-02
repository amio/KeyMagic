import AppKit
import QuartzCore
import SwiftUI

/// Displays script output in a transient Liquid Glass toast at the center of the screen.
@MainActor
public final class ScriptOutputPresenter {
    public init() {}
    private let model = ScriptOutputPresentationModel()
    private lazy var hostingView: NSHostingView<ScriptOutputToastContentView> = {
        let view = NSHostingView(rootView: ScriptOutputToastContentView(model: model))
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }()
    private lazy var toastView: ScriptOutputGlassToastView = {
        let view = ScriptOutputGlassToastView(contentView: hostingView)
        view.onHoverChanged = { [weak self] isHovering in
            self?.handleHoverChange(isHovering)
        }
        return view
    }()
    private lazy var panel: NSPanel = makePanel()
    private lazy var bodyAnimator = ScriptOutputSmootherstepAnimator(view: toastView)
    private var entranceTask: Task<Void, Never>?
    private var contentSwapTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var lifecycle = ScriptOutputToastLifecycle.hidden
    private var pendingItems: [ScriptOutputToastItem] = []
    private var remainingHoldDuration = TimeInterval.zero
    private var holdDeadline: TimeInterval?
    private var isPointerHovering = false

    /// How long the toast stays fully visible after its entrance animation.
    private let holdDuration: TimeInterval = 2

    public func show(log: ScriptExecutionLog) {
        guard let subtitleText = log.subtitleText else { return }
        let display = subtitleText.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard !display.isEmpty else { return }

        let item = ScriptOutputToastItem(
            text: display,
            textWidth: ScriptOutputToastMetrics.textWidth(for: display),
            isError: !log.succeeded
        )

        switch lifecycle {
        case .entering, .swapping:
            pendingItems.append(item)
        case .holding:
            resetHoldCountdown()
            startContentSwap(to: item)
        case .hidden, .dismissing:
            presentFresh(item)
        }
    }

    private func presentFresh(_ item: ScriptOutputToastItem) {
        if lifecycle != .hidden {
            persistVerticalPosition()
        }

        entranceTask?.cancel()
        contentSwapTask?.cancel()
        bodyAnimator.cancel()
        resetHoldCountdown()
        pendingItems.removeAll()
        model.currentItem = item
        model.nextItem = nil
        model.viewportTextWidth = item.textWidth
        model.contentSwapProgress = 0
        model.phase = .hidden
        model.contentRevealProgress = 0
        layoutPanel()
        panel.alphaValue = 0

        if lifecycle == .hidden {
            panel.orderFrontRegardless()
        }

        lifecycle = .entering
        playEntranceAnimation()
    }

    // MARK: - Panel Lifecycle

    private func beginHold() {
        remainingHoldDuration = holdDuration
        lifecycle = .holding
        isPointerHovering = toastView.isPointerInsideGlass

        if !isPointerHovering {
            resumeHoldCountdown()
        }
    }

    private func handleHoverChange(_ isHovering: Bool) {
        isPointerHovering = isHovering
        guard lifecycle == .holding else { return }

        if isHovering {
            pauseHoldCountdown()
        } else {
            resumeHoldCountdown()
        }
    }

    private func pauseHoldCountdown() {
        guard let holdDeadline else { return }

        remainingHoldDuration = max(
            0,
            holdDeadline - ProcessInfo.processInfo.systemUptime
        )
        self.holdDeadline = nil
        hideTask?.cancel()
        hideTask = nil
    }

    private func resumeHoldCountdown() {
        guard lifecycle == .holding, !isPointerHovering, hideTask == nil else { return }

        let duration = remainingHoldDuration
        holdDeadline = ProcessInfo.processInfo.systemUptime + duration
        hideTask = Task { [weak self] in
            guard let self else { return }

            guard await wait(for: duration) else { return }
            guard lifecycle == .holding, !isPointerHovering else { return }

            remainingHoldDuration = 0
            holdDeadline = nil
            lifecycle = .dismissing
            await dismissToast()
        }
    }

    private func resetHoldCountdown() {
        hideTask?.cancel()
        hideTask = nil
        remainingHoldDuration = holdDuration
        holdDeadline = nil
        isPointerHovering = false
    }

    private func playEntranceAnimation() {
        entranceTask = Task { [weak self] in
            guard let self else { return }

            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                applyBodyProgress(1)
                model.phase = .revealed
                panel.alphaValue = 1
                entranceTask = nil
                showNextPendingItemOrBeginHold()
                return
            }

            animatePanelAlpha(
                to: 1,
                duration: ScriptOutputToastTiming.appearanceDuration,
                timingFunction: CAMediaTimingFunction(name: .easeOut)
            )
            withAnimation(.easeOut(duration: ScriptOutputToastTiming.appearanceDuration)) {
                model.phase = .compact
            }

            guard await wait(for: ScriptOutputToastTiming.appearanceDuration) else { return }
            animateBody(from: 0, to: 1, duration: ScriptOutputToastTiming.expansionDuration)
            guard await wait(for: ScriptOutputToastTiming.expansionDuration) else { return }
            bodyAnimator.cancel()
            applyBodyProgress(1)
            model.phase = .revealed
            entranceTask = nil
            showNextPendingItemOrBeginHold()
        }
    }

    private func startContentSwap(to item: ScriptOutputToastItem) {
        lifecycle = .swapping

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishContentSwap(with: item)
            showNextPendingItemOrBeginHold()
            return
        }

        let startWidth = model.viewportTextWidth
        model.nextItem = item
        model.contentSwapProgress = 0
        contentSwapTask = Task { [weak self] in
            guard let self else { return }

            bodyAnimator.animate(
                from: 0,
                to: 1,
                duration: ScriptOutputToastTiming.contentSwapDuration
            ) { [weak self] progress in
                self?.applyContentSwapProgress(
                    progress,
                    fromTextWidth: startWidth,
                    toTextWidth: item.textWidth
                )
            }
            guard await wait(for: ScriptOutputToastTiming.contentSwapDuration) else { return }
            bodyAnimator.cancel()
            applyContentSwapProgress(
                1,
                fromTextWidth: startWidth,
                toTextWidth: item.textWidth
            )
            finishContentSwap(with: item)
            contentSwapTask = nil
            showNextPendingItemOrBeginHold()
        }
    }

    private func applyContentSwapProgress(
        _ progress: CGFloat,
        fromTextWidth: CGFloat,
        toTextWidth: CGFloat
    ) {
        model.contentSwapProgress = progress
        let textWidth = fromTextWidth + (toTextWidth - fromTextWidth) * progress
        model.viewportTextWidth = textWidth
        resizeExpandedPanel(textWidth: textWidth)
    }

    private func finishContentSwap(with item: ScriptOutputToastItem) {
        model.currentItem = item
        model.nextItem = nil
        model.viewportTextWidth = item.textWidth
        model.contentSwapProgress = 0
        resizeExpandedPanel(textWidth: item.textWidth)
    }

    private func showNextPendingItemOrBeginHold() {
        guard !pendingItems.isEmpty else {
            beginHold()
            return
        }

        startContentSwap(to: pendingItems.removeFirst())
    }

    private func dismissToast() async {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            model.phase = .compact
            animateBody(from: 1, to: 0, duration: ScriptOutputToastTiming.collapseDuration)
            guard await wait(for: ScriptOutputToastTiming.collapseDuration) else { return }
            bodyAnimator.cancel()
            applyBodyProgress(0)

            animatePanelAlpha(
                to: 0,
                duration: ScriptOutputToastTiming.appearanceDuration,
                timingFunction: CAMediaTimingFunction(name: .easeIn)
            )
            withAnimation(.easeIn(duration: ScriptOutputToastTiming.appearanceDuration)) {
                model.phase = .hidden
            }
            guard await wait(for: ScriptOutputToastTiming.appearanceDuration) else { return }
        } else {
            panel.alphaValue = 0
        }

        persistVerticalPosition()
        lifecycle = .hidden
        isPointerHovering = false
        panel.orderOut(nil)
    }

    private func animateBody(from start: CGFloat, to end: CGFloat, duration: TimeInterval) {
        bodyAnimator.animate(from: start, to: end, duration: duration) { [weak self] progress in
            self?.applyBodyProgress(progress)
        }
    }

    private func applyBodyProgress(_ progress: CGFloat) {
        toastView.setExpansionProgress(progress)
        model.contentRevealProgress = progress
    }

    private func resizeExpandedPanel(textWidth: CGFloat) {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let contentSize = ScriptOutputToastMetrics.contentSize(forTextWidth: textWidth)
        let panelSize = ScriptOutputGlassToastView.panelSize(for: contentSize)
        panel.setFrame(
            NSRect(
                x: center.x - panelSize.width / 2,
                y: center.y - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            ),
            display: true
        )
        toastView.updateExpandedContentSize(contentSize)
        toastView.setExpansionProgress(1)
    }

    private func animatePanelAlpha(
        to alpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            panel.animator().alphaValue = alpha
        }
    }

    private func wait(for duration: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func layoutPanel() {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize
        let panelSize = ScriptOutputGlassToastView.panelSize(for: contentSize)
        panel.setContentSize(panelSize)
        toastView.prepare(expandedContentSize: contentSize)

        guard let screen = targetScreen() else { return }

        let frame = screen.visibleFrame
        let verticalPosition = preferredVerticalPositionFromTop()
        let desiredOriginY =
            frame.maxY - frame.height * verticalPosition - panelSize.height / 2
        let maximumOriginY = max(frame.minY, frame.maxY - panelSize.height)
        let origin = CGPoint(
            x: frame.midX - panelSize.width / 2,
            y: min(max(desiredOriginY, frame.minY), maximumOriginY)
        )
        panel.setFrameOrigin(origin)
    }

    private func preferredVerticalPositionFromTop() -> CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ScriptOutputToastPosition.defaultsKey) != nil else {
            return ScriptOutputToastPosition.defaultVerticalPositionFromTop
        }

        let storedPosition = defaults.double(forKey: ScriptOutputToastPosition.defaultsKey)
        guard storedPosition.isFinite else {
            return ScriptOutputToastPosition.defaultVerticalPositionFromTop
        }
        return min(max(CGFloat(storedPosition), 0), 1)
    }

    private func persistVerticalPosition() {
        guard let screen = panel.screen, screen.visibleFrame.height > 0 else { return }

        let visibleFrame = screen.visibleFrame
        let positionFromTop = (visibleFrame.maxY - panel.frame.midY) / visibleFrame.height
        let normalizedPosition = min(max(positionFromTop, 0), 1)
        UserDefaults.standard.set(
            Double(normalizedPosition),
            forKey: ScriptOutputToastPosition.defaultsKey
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = toastView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
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
}

// MARK: - Presentation Model

private enum ScriptOutputToastLifecycle {
    case hidden
    case entering
    case holding
    case swapping
    case dismissing
}

private struct ScriptOutputToastItem {
    static let empty = ScriptOutputToastItem(text: "", textWidth: 0, isError: false)

    let text: String
    let textWidth: CGFloat
    let isError: Bool
}

@Observable
@MainActor
private final class ScriptOutputPresentationModel {
    var currentItem = ScriptOutputToastItem.empty
    var nextItem: ScriptOutputToastItem?
    var viewportTextWidth = CGFloat.zero
    var contentRevealProgress = CGFloat.zero
    var contentSwapProgress = CGFloat.zero
    var phase = ScriptOutputToastPhase.compact
}

// MARK: - Toast View

private enum ScriptOutputToastTiming {
    static let appearanceDuration: TimeInterval = 0.18
    static let expansionDuration: TimeInterval = 0.46
    static let collapseDuration = expansionDuration
    static let contentSwapDuration: TimeInterval = 0.32

    static func smootherstep(_ progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

@MainActor
private final class ScriptOutputSmootherstepAnimator: NSObject {
    private weak var view: NSView?
    private var displayLink: CADisplayLink?
    private var startTime = CFTimeInterval.zero
    private var duration = TimeInterval.zero
    private var startValue = CGFloat.zero
    private var endValue = CGFloat.zero
    private var update: ((CGFloat) -> Void)?

    init(view: NSView) {
        self.view = view
    }

    func animate(
        from startValue: CGFloat,
        to endValue: CGFloat,
        duration: TimeInterval,
        update: @escaping (CGFloat) -> Void
    ) {
        cancel()
        self.startValue = startValue
        self.endValue = endValue
        self.duration = max(duration, .leastNonzeroMagnitude)
        self.update = update
        startTime = CACurrentMediaTime()
        update(startValue)

        guard
            let displayLink = view?.displayLink(
                target: self,
                selector: #selector(handleDisplayLink(_:))
            )
        else {
            update(endValue)
            self.update = nil
            return
        }

        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        update = nil
    }

    @objc
    private func handleDisplayLink(_ displayLink: CADisplayLink) {
        let elapsed = displayLink.timestamp - startTime
        let linearProgress = CGFloat(min(max(elapsed / duration, 0), 1))
        let curvedProgress = ScriptOutputToastTiming.smootherstep(linearProgress)
        update?(startValue + (endValue - startValue) * curvedProgress)

        if linearProgress >= 1 {
            cancel()
        }
    }
}

private enum ScriptOutputToastPosition {
    static let defaultsKey = "scriptOutputToastVerticalPositionFromTop"
    static let defaultVerticalPositionFromTop: CGFloat = 0.75
}

@MainActor
private enum ScriptOutputToastMetrics {
    static let collapsedDiameter: CGFloat = 58
    static let horizontalPadding: CGFloat = 12
    static let contentSpacing: CGFloat = 13
    static let statusSymbolSize: CGFloat = 34
    static let statusGlyphSize: CGFloat = 18
    static let maximumTextWidth: CGFloat = 600

    private static let textFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)

    static func textWidth(for text: String) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textFont],
            context: nil
        )
        return min(maximumTextWidth, ceil(max(1, bounds.width)))
    }

    static func contentSize(forTextWidth textWidth: CGFloat) -> NSSize {
        NSSize(
            width: horizontalPadding * 2 + statusSymbolSize + contentSpacing + textWidth,
            height: collapsedDiameter
        )
    }
}

private enum ScriptOutputToastPhase {
    case hidden
    case compact
    case revealed

    var iconScale: CGFloat {
        switch self {
        case .hidden: 0
        case .compact, .revealed: 1
        }
    }
}

private struct ScriptOutputToastContentView: View {
    let model: ScriptOutputPresentationModel

    var body: some View {
        ZStack(alignment: .leading) {
            toastContent(item: model.currentItem, phase: model.phase)
                .offset(y: -model.contentSwapProgress * ScriptOutputToastMetrics.collapsedDiameter)

            if let nextItem = model.nextItem {
                toastContent(item: nextItem, phase: model.phase)
                    .offset(
                        y: (1 - model.contentSwapProgress)
                            * ScriptOutputToastMetrics.collapsedDiameter
                    )
            }
        }
        .frame(
            width: ScriptOutputToastMetrics.contentSize(
                forTextWidth: model.viewportTextWidth
            ).width,
            height: ScriptOutputToastMetrics.collapsedDiameter,
            alignment: .leading
        )
        .clipped()
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityItem.isError ? "Script failed" : "Script completed")
        .accessibilityValue(accessibilityItem.text)
    }

    private var accessibilityItem: ScriptOutputToastItem {
        model.nextItem ?? model.currentItem
    }

    private func toastContent(
        item: ScriptOutputToastItem,
        phase: ScriptOutputToastPhase
    ) -> some View {
        HStack(spacing: ScriptOutputToastMetrics.contentSpacing) {
            statusSymbol(isError: item.isError, phase: phase)

            Text(item.text)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: item.textWidth, alignment: .leading)
                .mask {
                    ScriptOutputTextRevealMask(
                        progress: model.contentRevealProgress,
                        width: item.textWidth
                    )
                }
        }
        .padding(.horizontal, ScriptOutputToastMetrics.horizontalPadding)
        .padding(.vertical, 12)
        .frame(minHeight: ScriptOutputToastMetrics.collapsedDiameter, alignment: .leading)
    }

    private func statusSymbol(
        isError: Bool,
        phase: ScriptOutputToastPhase
    ) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.72), lineWidth: 1.5)

            Image(systemName: isError ? "exclamationmark" : "checkmark")
                .font(.system(size: ScriptOutputToastMetrics.statusGlyphSize, weight: .bold))
        }
        .foregroundStyle(.primary)
        .frame(
            width: ScriptOutputToastMetrics.statusSymbolSize,
            height: ScriptOutputToastMetrics.statusSymbolSize
        )
        .scaleEffect(phase.iconScale)
        .accessibilityHidden(true)
    }
}

private struct ScriptOutputTextRevealMask: View {
    private static let featherWidth: CGFloat = 28

    let progress: CGFloat
    let width: CGFloat

    private var revealEdge: CGFloat {
        let expandedEdge = width + ScriptOutputToastMetrics.horizontalPadding
        return progress * expandedEdge
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.white)
                .frame(width: width)

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.featherWidth)
        }
        // Tie the left-to-right feathered reveal to the symmetric Glass expansion progress.
        .offset(x: revealEdge - (width + Self.featherWidth))
        .frame(width: width, alignment: .leading)
        .clipped()
    }
}

/// Owns the native Glass surface at the panel boundary so AppKit can composite its hosted content.
private final class ScriptOutputGlassToastView: NSView {
    private static let panelPadding: CGFloat = 24

    var onHoverChanged: ((Bool) -> Void)?

    private let glassView: NSGlassEffectView
    private let glassContentView: ScriptOutputGlassContentView
    private var expandedContentSize = NSSize(
        width: ScriptOutputToastMetrics.collapsedDiameter,
        height: ScriptOutputToastMetrics.collapsedDiameter
    )

    init(contentView: NSView) {
        glassContentView = ScriptOutputGlassContentView(hostedView: contentView)
        glassView = NSGlassEffectView()
        super.init(frame: .zero)

        glassView.style = .regular
        glassView.contentView = glassContentView
        addSubview(glassView)
        glassView.addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func panelSize(for contentSize: NSSize) -> NSSize {
        NSSize(
            width: contentSize.width + panelPadding * 2,
            height: contentSize.height + panelPadding * 2
        )
    }

    var isPointerInsideGlass: Bool {
        guard let window else { return false }
        let location = glassView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return glassView.bounds.contains(location)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        glassView.frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    func prepare(expandedContentSize: NSSize) {
        updateExpandedContentSize(expandedContentSize)
        showCompact()
    }

    func updateExpandedContentSize(_ expandedContentSize: NSSize) {
        self.expandedContentSize = expandedContentSize
        glassContentView.expandedContentSize = expandedContentSize
    }

    func showCompact() {
        glassView.layer?.removeAllAnimations()
        setExpansionProgress(0)
    }

    func setExpansionProgress(_ progress: CGFloat) {
        let t = min(max(progress, 0), 1)
        let compactFrame = compactFrame
        let expandedFrame = expandedFrame
        let frame = NSRect(
            x: compactFrame.minX + (expandedFrame.minX - compactFrame.minX) * t,
            y: compactFrame.minY + (expandedFrame.minY - compactFrame.minY) * t,
            width: compactFrame.width + (expandedFrame.width - compactFrame.width) * t,
            height: compactFrame.height + (expandedFrame.height - compactFrame.height) * t
        )
        glassView.frame = frame
        glassView.cornerRadius = min(
            ScriptOutputToastMetrics.collapsedDiameter / 2,
            frame.height / 2
        )
    }

    private var compactFrame: NSRect {
        let diameter = ScriptOutputToastMetrics.collapsedDiameter
        return NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    private var expandedFrame: NSRect {
        NSRect(
            x: Self.panelPadding,
            y: Self.panelPadding,
            width: expandedContentSize.width,
            height: expandedContentSize.height
        )
    }
}

/// Keeps the icon and text aligned to the moving left edge of the Glass surface.
private final class ScriptOutputGlassContentView: NSView {
    var expandedContentSize = NSSize.zero {
        didSet { needsLayout = true }
    }

    private let hostedView: NSView

    init(hostedView: NSView) {
        self.hostedView = hostedView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(hostedView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hostedView.frame = NSRect(
            x: 0,
            y: (bounds.height - expandedContentSize.height) / 2,
            width: expandedContentSize.width,
            height: expandedContentSize.height
        )
    }
}
