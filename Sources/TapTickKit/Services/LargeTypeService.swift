import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

/// Owns the complete Large Type presentation session: panel lifecycle, native text input,
/// adaptive layout, QR generation, and returning focus after an explicit dismissal.
@MainActor
final class LargeTypeService {
    private let model = LargeTypePresentationModel()
    private lazy var hostingView = NSHostingView(
        rootView: LargeTypeOverlay(
            model: model,
            onDismiss: { [weak self] in
                self?.dismiss(restoreFocus: true)
            }
        )
    )
    private lazy var panel = makePanel()

    private var configuration = LargeTypeConfiguration.default
    private var previouslyActiveApplication: NSRunningApplication?
    private var dismissalTask: Task<Void, Never>?
    private var isPresented = false
    private var isDismissing = false

    func apply(configuration: LargeTypeConfiguration) {
        self.configuration = configuration
        model.apply(configuration: configuration)

        if !configuration.isEnabled, isPresented {
            dismiss(restoreFocus: true, animated: false)
        }
    }

    func toggle(configuration: LargeTypeConfiguration) {
        apply(configuration: configuration)
        guard configuration.isEnabled else { return }

        if isPresented {
            dismiss(restoreFocus: true)
        } else {
            present()
        }
    }

    private func present() {
        guard let screen = targetScreen() else { return }

        dismissalTask?.cancel()
        dismissalTask = nil
        isDismissing = false

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmostApplication
        } else {
            previouslyActiveApplication = nil
        }

        model.beginSession(configuration: configuration)
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.unhide(nil)
        NSApp.activate()
        panel.makeKey()
        isPresented = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func dismiss(
        restoreFocus: Bool,
        animated: Bool = true
    ) {
        guard isPresented, !isDismissing else { return }

        isPresented = false
        isDismissing = true
        dismissalTask?.cancel()

        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 0
            self.isDismissing = false
            self.model.endSession()

            guard restoreFocus else {
                self.previouslyActiveApplication = nil
                return
            }

            let target = self.previouslyActiveApplication
            self.previouslyActiveApplication = nil
            guard let target, !target.isTerminated else {
                NSApp.hide(nil)
                return
            }

            NSApp.yieldActivation(to: target)
            target.activate()
        }

        guard animated else {
            finish()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else { return }
            finish()
            self?.dismissalTask = nil
        }
    }

    private func makePanel() -> LargeTypePanel {
        let panel = LargeTypePanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let container = NSView(frame: .zero)
        let blurView = NSVisualEffectView(frame: .zero)
        blurView.material = .underWindowBackground
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(blurView)
        container.addSubview(hostingView)

        panel.contentView = container
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.onResignKey = { [weak self] in
            self?.dismiss(restoreFocus: false, animated: false)
        }

        return panel
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }
}

@MainActor
private final class LargeTypePanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@Observable
@MainActor
private final class LargeTypePresentationModel {
    var text = "" {
        didSet {
            guard showsQRCode else { return }
            updateQRCode()
        }
    }

    var showsQRCode = false
    var qrCodeImage: NSImage?
    var focusRevision = 0
    var fontFamily: String?
    var foregroundColor = LargeTypeConfiguration.default.foregroundColor.color
    var backgroundColor = LargeTypeConfiguration.default.backgroundColor.color

    func beginSession(configuration: LargeTypeConfiguration) {
        apply(configuration: configuration)
        text = ""
        showsQRCode = false
        qrCodeImage = nil
        focusRevision += 1
    }

    func endSession() {
        text = ""
        showsQRCode = false
        qrCodeImage = nil
    }

    func apply(configuration: LargeTypeConfiguration) {
        fontFamily = configuration.fontFamily
        foregroundColor = configuration.foregroundColor.color
        backgroundColor = configuration.backgroundColor.color
    }

    func toggleQRCode() {
        guard !text.isEmpty else { return }
        showsQRCode.toggle()
        if showsQRCode {
            updateQRCode()
        }
        focusRevision += 1
    }

    private func updateQRCode() {
        qrCodeImage = LargeTypeQRCodeRenderer.image(for: text)
    }
}

@MainActor
private enum LargeTypeQRCodeRenderer {
    static func image(for text: String) -> NSImage? {
        guard !text.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scaledImage = outputImage.transformed(
            by: CGAffineTransform(scaleX: 12, y: 12)
        )
        let representation = NSCIImageRep(ciImage: scaledImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

struct LargeTypeLayout: Equatable, Sendable {
    let fontSize: CGFloat
    let lineLimit: Int
}

struct LargeTypeOptionKeyGesture: Equatable, Sendable {
    private(set) var isPressed = false
    private var wasUsedWithAnotherKey = false

    mutating func handleFlagsChanged(
        optionIsActive: Bool,
        hasOtherModifiers: Bool
    ) -> Bool {
        if optionIsActive, !isPressed {
            isPressed = true
            wasUsedWithAnotherKey = hasOtherModifiers
            return false
        }

        if optionIsActive, hasOtherModifiers {
            wasUsedWithAnotherKey = true
            return false
        }

        guard !optionIsActive, isPressed else { return false }

        isPressed = false
        let shouldToggle = !wasUsedWithAnotherKey
        wasUsedWithAnotherKey = false
        return shouldToggle
    }

    mutating func handleKeyDown() {
        if isPressed {
            wasUsedWithAnotherKey = true
        }
    }
}

/// Selects the fewest permitted lines that keep each fitted line at or above the
/// progressive screen-height threshold: 1/2, 1/3, 1/4, and so on.
@MainActor
enum LargeTypeLayoutEngine {
    static func layout(
        text: String,
        in availableSize: CGSize,
        screenHeight: CGFloat,
        fontFamily: String?
    ) -> LargeTypeLayout {
        guard !text.isEmpty, availableSize.width > 0, availableSize.height > 0 else {
            return LargeTypeLayout(fontSize: max(screenHeight * 0.22, 48), lineLimit: 1)
        }

        var lastFittingLayout = LargeTypeLayout(fontSize: 1, lineLimit: 1)
        let maximumLineCount = max(1, min(48, Int(screenHeight / 12)))

        for lineLimit in 1...maximumLineCount {
            let fit = maximumFit(
                text: text,
                in: availableSize,
                maximumLineCount: lineLimit,
                fontFamily: fontFamily
            )

            guard fit.fits else { continue }

            lastFittingLayout = LargeTypeLayout(
                fontSize: max(1, fit.fontSize * 0.985),
                lineLimit: lineLimit
            )

            let minimumLineHeight = screenHeight / CGFloat(lineLimit + 1)
            if fit.lineHeight >= minimumLineHeight {
                return lastFittingLayout
            }
        }

        return lastFittingLayout
    }

    static func font(family: String?, size: CGFloat) -> NSFont {
        if let family,
            let font = NSFontManager.shared.font(
                withFamily: family,
                traits: [],
                weight: 5,
                size: size
            )
        {
            return font
        }

        return NSFont.systemFont(ofSize: size, weight: .regular)
    }

    private static func maximumFit(
        text: String,
        in availableSize: CGSize,
        maximumLineCount: Int,
        fontFamily: String?
    ) -> FontFit {
        var lowerBound: CGFloat = 1
        var upperBound = max(availableSize.width, availableSize.height) * 2
        var bestFit: FontFit?

        for _ in 0..<18 {
            let candidateSize = (lowerBound + upperBound) / 2
            let measurement = measure(
                text: text,
                width: availableSize.width,
                font: font(family: fontFamily, size: candidateSize)
            )
            let fits =
                measurement.lineCount <= maximumLineCount
                && measurement.usedSize.height <= availableSize.height + 0.5
                && measurement.usedSize.width <= availableSize.width + 0.5

            if fits {
                let fit = FontFit(
                    fontSize: candidateSize,
                    lineHeight: measurement.lineHeight,
                    fits: true
                )
                bestFit = fit
                lowerBound = candidateSize
            } else {
                upperBound = candidateSize
            }
        }

        if let bestFit {
            return bestFit
        }

        let fallbackFont = font(family: fontFamily, size: 1)
        let fallbackMeasurement = measure(
            text: text,
            width: availableSize.width,
            font: fallbackFont
        )
        return FontFit(
            fontSize: 1,
            lineHeight: fallbackMeasurement.lineHeight,
            fits: fallbackMeasurement.lineCount <= maximumLineCount
                && fallbackMeasurement.usedSize.height <= availableSize.height + 0.5
        )
    }

    private static func measure(
        text: String,
        width: CGFloat,
        font: NSFont
    ) -> TextMeasurement {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .center

        let storage = NSTextStorage(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        var lineCount = 0
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineRange = NSRange()
            layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineRange
            )
            lineCount += 1
            glyphIndex = NSMaxRange(lineRange)
        }

        let explicitLineCount = text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        return TextMeasurement(
            usedSize: layoutManager.usedRect(for: container).size,
            lineCount: max(lineCount, explicitLineCount),
            lineHeight: lineHeight
        )
    }

    private struct FontFit {
        let fontSize: CGFloat
        let lineHeight: CGFloat
        let fits: Bool
    }

    private struct TextMeasurement {
        let usedSize: CGSize
        let lineCount: Int
        let lineHeight: CGFloat
    }
}

private struct LargeTypeOverlay: View {
    @Bindable var model: LargeTypePresentationModel
    let onDismiss: () -> Void
    @State private var isHoveringQRToggle = false

    private static let transitionDuration = 0.36
    private static let qrTransitionDuration = transitionDuration * 2 / 3

    private let layoutAnimation = Animation.easeOut(duration: transitionDuration)
    private let qrInsertionAnimation =
        Animation
        .easeOut(duration: qrTransitionDuration)
        .delay(transitionDuration / 3)
    private let qrRemovalAnimation = Animation.easeOut(duration: qrTransitionDuration)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let textWidth = size.width * (model.showsQRCode ? 0.43 : 0.84)
            let textHeight = size.height * 0.72
            let layout = LargeTypeLayoutEngine.layout(
                text: model.text,
                in: CGSize(width: textWidth, height: textHeight),
                screenHeight: size.height,
                fontFamily: model.fontFamily
            )

            ZStack {
                Rectangle()
                    .fill(model.backgroundColor)
                    .ignoresSafeArea()

                textPresentation(layout: layout)
                    .frame(width: textWidth, height: textHeight)
                    .position(
                        x: size.width * (model.showsQRCode ? 0.265 : 0.5),
                        y: size.height * 0.49
                    )

                if model.showsQRCode {
                    qrCodePresentation
                        .frame(
                            width: min(size.width * 0.36, size.height * 0.62),
                            height: min(size.width * 0.36, size.height * 0.62)
                        )
                        .position(x: size.width * 0.745, y: size.height * 0.49)
                        .transition(
                            .asymmetric(
                                insertion: qrTransition.animation(qrInsertionAnimation),
                                removal: qrTransition.animation(qrRemovalAnimation)
                            )
                        )
                }

                LargeTypeTextInput(
                    text: Binding(
                        get: { model.text },
                        set: { model.text = $0 }
                    ),
                    focusRevision: model.focusRevision,
                    onCancel: onDismiss,
                    onToggleQRCode: {
                        withAnimation(layoutAnimation) {
                            model.toggleQRCode()
                        }
                    }
                )
                .frame(width: 2, height: 2)
                .position(x: size.width / 2, y: size.height / 2)
                .opacity(0.001)

                qrToggleButton
                    .position(x: size.width / 2, y: size.height - 32)
            }
            .animation(layoutAnimation, value: model.showsQRCode)
        }
    }

    private var qrTransition: AnyTransition {
        .scale(scale: 0.9, anchor: .trailing)
            .combined(with: .opacity)
    }

    @ViewBuilder
    private func textPresentation(layout: LargeTypeLayout) -> some View {
        if model.text.isEmpty {
            BlinkingLargeTypeCaret(color: model.foregroundColor)
        } else {
            Text(model.text)
                .font(presentationFont(size: layout.fontSize))
                .foregroundStyle(model.foregroundColor)
                .multilineTextAlignment(.center)
                .lineLimit(layout.lineLimit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel(model.text)
        }
    }

    private func presentationFont(size: CGFloat) -> Font {
        if let family = model.fontFamily {
            return .custom(family, size: size)
        }

        return .system(size: size, weight: .regular)
    }

    private var qrCodePresentation: some View {
        Group {
            if let image = model.qrCodeImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 42, weight: .light))
                    Text("Text is too long for a QR code")
                        .font(.headline)
                }
                .foregroundStyle(model.foregroundColor.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("QR code for entered text")
    }

    private var qrToggleButton: some View {
        Button {
            withAnimation(layoutAnimation) {
                model.toggleQRCode()
            }
        } label: {
            Image(systemName: model.showsQRCode ? "textformat" : "qrcode")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(
                    model.foregroundColor.opacity(
                        model.text.isEmpty ? 0.16 : (isHoveringQRToggle ? 0.68 : 0.42)
                    )
                )
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(
                            model.foregroundColor.opacity(
                                isHoveringQRToggle && !model.text.isEmpty ? 0.11 : 0
                            )
                        )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.text.isEmpty)
        .help(model.showsQRCode ? "Show text only · ⌥" : "Show QR code · ⌥")
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringQRToggle = isHovering
            }
        }
        .accessibilityLabel(model.showsQRCode ? "Show text only" : "Show QR code")
    }
}

private struct BlinkingLargeTypeCaret: View {
    let color: Color
    @State private var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 5, height: 156)
            .opacity(isDimmed ? 0.12 : 0.88)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.56).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
            .accessibilityHidden(true)
    }
}

private struct LargeTypeTextInput: NSViewRepresentable {
    @Binding var text: String
    let focusRevision: Int
    let onCancel: () -> Void
    let onToggleQRCode: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> LargeTypeInputTextView {
        let textView = LargeTypeInputTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textColor = .clear
        textView.insertionPointColor = .clear
        textView.font = .systemFont(ofSize: 1)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.onCancel = onCancel
        textView.onToggleQRCode = onToggleQRCode
        textView.string = text
        return textView
    }

    func updateNSView(_ textView: LargeTypeInputTextView, context: Context) {
        context.coordinator.parent = self
        textView.onCancel = onCancel
        textView.onToggleQRCode = onToggleQRCode

        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }

        guard context.coordinator.lastFocusRevision != focusRevision else { return }
        context.coordinator.lastFocusRevision = focusRevision
        textView.requestFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LargeTypeTextInput
        var lastFocusRevision = -1

        init(parent: LargeTypeTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

@MainActor
private final class LargeTypeInputTextView: NSTextView {
    var onCancel: (() -> Void)?
    var onToggleQRCode: (() -> Void)?
    private var shouldBecomeFirstResponder = false
    private var optionKeyGesture = LargeTypeOptionKeyGesture()

    override func draw(_ dirtyRect: NSRect) {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        fulfillFirstResponderRequestIfPossible()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        optionKeyGesture.handleKeyDown()
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let otherRelevantModifiers: NSEvent.ModifierFlags = [
            .command,
            .control,
            .shift,
            .function,
        ]

        if optionKeyGesture.handleFlagsChanged(
            optionIsActive: flags.contains(.option),
            hasOtherModifiers: !flags.intersection(otherRelevantModifiers).isEmpty
        ) {
            onToggleQRCode?()
        }

        super.flagsChanged(with: event)
    }

    func requestFirstResponder() {
        shouldBecomeFirstResponder = true
        fulfillFirstResponderRequestIfPossible()
    }

    private func fulfillFirstResponderRequestIfPossible() {
        guard shouldBecomeFirstResponder, let window else { return }
        shouldBecomeFirstResponder = false
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
