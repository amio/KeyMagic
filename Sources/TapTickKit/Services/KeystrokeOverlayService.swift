import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Observation
import SwiftUI

@MainActor
final class KeystrokeOverlayService {
    var onPermissionChange: ((EventListeningPermissionStatus) -> Void)?
    var onCaptureStateChange: ((Bool) -> Void)?

    private let presenter = KeystrokeOverlayPresenter()
    private let preflightPermissionAccess: () -> Bool
    private let requestPermissionAccess: () -> Bool
    private let openURL: (URL) -> Bool

    private var configuration = KeystrokeOverlayConfiguration.default
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// After a combo keyDown, suppress flagsChanged until all modifiers are released.
    private var suppressFlagsUntilRelease = false
    /// Accumulated bare characters for consecutive typing (e.g. "HELLO").
    private var accumulatedText: String?
    /// Timestamp of the last event presentation, used as the merge-window reference.
    private var lastShowTimestamp: CFAbsoluteTime = 0

    init(
        preflightPermissionAccess: @escaping () -> Bool = CGPreflightListenEventAccess,
        requestPermissionAccess: @escaping () -> Bool = CGRequestListenEventAccess,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.preflightPermissionAccess = preflightPermissionAccess
        self.requestPermissionAccess = requestPermissionAccess
        self.openURL = openURL
    }

    func refreshPermissionStatus() -> EventListeningPermissionStatus {
        notifyPermissionStatus(currentPermissionStatus())
    }

    func requestPermission() -> EventListeningPermissionStatus {
        if preflightPermissionAccess() {
            return notifyPermissionStatus(.granted)
        }

        let granted = requestPermissionAccess()
        if !granted {
            openInputMonitoringSettings()
        }
        return notifyPermissionStatus(granted ? .granted : .denied)
    }

    /// Show a settings-driven preview HUD using the given configuration. Works
    /// regardless of whether the overlay is enabled and keeps the HUD alive for
    /// one full visible-time interval from the latest settings change.
    func showPreview(configuration: KeystrokeOverlayConfiguration) {
        presenter.showPreview(text: configuration.hotkey.displayString, configuration: configuration)
    }

    func apply(
        configuration: KeystrokeOverlayConfiguration,
        promptForPermission: Bool
    ) -> EventListeningPermissionStatus {
        self.configuration = configuration
        presenter.update(configuration: configuration)

        guard configuration.isEnabled else {
            stopCapture()
            return notifyPermissionStatus(currentPermissionStatus())
        }

        let permissionStatus = promptForPermission
            ? requestPermission()
            : refreshPermissionStatus()

        guard permissionStatus == .granted else {
            stopCapture()
            return permissionStatus
        }

        let wasCapturing = eventTap != nil
        startCaptureIfNeeded()
        // The toggle hotkey's modifier keys are still held; suppress the
        // upcoming flagsChanged releases so the overlay doesn't flash "⌥" etc.
        suppressFlagsUntilRelease = true

        if !wasCapturing, eventTap != nil {
            presenter.showEvent(text: "Keystroke Overlay On", configuration: configuration)
        }

        return permissionStatus
    }

    private func startCaptureIfNeeded() {
        guard eventTap == nil else {
            notifyCaptureState(true)
            return
        }

        let eventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: keystrokeOverlayEventTapCallback,
            userInfo: userInfo
        ) else {
            notifyCaptureState(false)
            _ = notifyPermissionStatus(currentPermissionStatus())
            return
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            notifyCaptureState(false)
            return
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        notifyCaptureState(true)
    }

    private func stopCapture() {
        presenter.dismissEventPresentationIfNeeded()
        suppressFlagsUntilRelease = false
        accumulatedText = nil

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        notifyCaptureState(false)
    }

    private func notifyPermissionStatus(_ status: EventListeningPermissionStatus) -> EventListeningPermissionStatus {
        onPermissionChange?(status)
        return status
    }

    private func notifyCaptureState(_ isCapturing: Bool) {
        onCaptureStateChange?(isCapturing)
    }

    private func currentPermissionStatus() -> EventListeningPermissionStatus {
        preflightPermissionAccess() ? .granted : .denied
    }

    @discardableResult
    private func openInputMonitoringSettings() -> Bool {
        for candidate in Self.inputMonitoringSettingsURLs {
            if openURL(candidate) {
                return true
            }
        }
        return false
    }

    private static let inputMonitoringSettingsURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security")!,
    ]

    fileprivate func handleEvent(type: CGEventType, keyCode: UInt32, modifiers: KeyCombo.Modifiers) {
        switch type {
        case .tapDisabledByTimeout:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                notifyCaptureState(true)
            }
        case .tapDisabledByUserInput:
            stopCapture()
        case .flagsChanged:
            guard configuration.isEnabled else { return }
            handleFlagsChanged(modifiers: modifiers)
        case .keyDown:
            guard configuration.isEnabled else { return }
            handleKeyDown(keyCode: keyCode, modifiers: modifiers)
        default:
            break
        }
    }

    // MARK: - Event State Machine

    private func handleFlagsChanged(modifiers: KeyCombo.Modifiers) {
        // Any modifier activity breaks character accumulation
        accumulatedText = nil

        if presenter.isPreviewActive {
            if modifiers.isEmpty {
                suppressFlagsUntilRelease = false
            }
            return
        }

        // After a combo keyDown, suppress all flagsChanged until full release
        if suppressFlagsUntilRelease {
            if modifiers.isEmpty {
                suppressFlagsUntilRelease = false
            }
            return
        }

        guard !modifiers.isEmpty else { return }
        presenter.showEvent(text: modifiers.displayString, configuration: configuration)
    }

    private func handleKeyDown(keyCode: UInt32, modifiers: KeyCombo.Modifiers) {
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard combo != configuration.hotkey else { return }

        if presenter.isPreviewActive {
            accumulatedText = nil
            lastShowTimestamp = 0
            return
        }

        if modifiers.isEmpty {
            suppressFlagsUntilRelease = false

            if Self.isTypeableCharacter(keyCode) {
                let keyName = Self.typeableDisplayName(for: keyCode)
                let now = CFAbsoluteTimeGetCurrent()
                if let existing = accumulatedText,
                   now - lastShowTimestamp < configuration.holdDuration {
                    accumulatedText = existing + keyName
                } else {
                    accumulatedText = keyName
                }
                lastShowTimestamp = now
                presenter.showEvent(text: accumulatedText!, configuration: configuration)
            } else {
                // Non-typeable key (Return, arrows, function keys …) — show standalone
                let keyName = KeyCodeMapping.keyName(for: keyCode)
                accumulatedText = nil
                lastShowTimestamp = CFAbsoluteTimeGetCurrent()
                presenter.showEvent(text: keyName, configuration: configuration)
            }
        } else {
            // Combo with modifiers — show and arm suppression
            accumulatedText = nil
            suppressFlagsUntilRelease = true
            lastShowTimestamp = CFAbsoluteTimeGetCurrent()
            presenter.showEvent(text: combo.displayString, configuration: configuration)
        }
    }

    /// A key is "typeable" when it represents a character the user is typing:
    /// letters, digits, punctuation, and space. Multi-character names like "F1"
    /// and Unicode symbols like "↩" or "⌫" are excluded — they display standalone
    /// and break any ongoing text accumulation.
    private static func isTypeableCharacter(_ keyCode: UInt32) -> Bool {
        if Int(keyCode) == kVK_Space { return true }
        let name = KeyCodeMapping.keyName(for: keyCode)
        guard let scalar = name.unicodeScalars.first,
              name.unicodeScalars.count == 1 else {
            return false
        }
        return scalar.value >= 0x21 && scalar.value <= 0x7E
    }

    /// Display name used inside accumulated text. Space renders as a literal
    /// whitespace character instead of the symbolic "Space" label.
    private static func typeableDisplayName(for keyCode: UInt32) -> String {
        if Int(keyCode) == kVK_Space { return " " }
        return KeyCodeMapping.keyName(for: keyCode)
    }
}

struct KeystrokeOverlayPresentationCoordinator {
    enum Intent {
        case event
        case preview
    }

    enum CaptureShutdownDisposition {
        case hidePresentation
        case keepPresentation
    }

    private(set) var activeIntent: Intent?

    var isPreviewActive: Bool {
        activeIntent == .preview
    }

    var allowsEventPresentation: Bool {
        activeIntent != .preview
    }

    mutating func begin(_ intent: Intent) {
        activeIntent = intent
    }

    mutating func finishPresentation() {
        activeIntent = nil
    }

    mutating func stopCapture() -> CaptureShutdownDisposition {
        guard activeIntent == .event else {
            return .keepPresentation
        }

        activeIntent = nil
        return .hidePresentation
    }
}

@MainActor
private final class KeystrokeOverlayPresenter {
    private let model = KeystrokeOverlayPresentationModel()
    private lazy var hostingView = NSHostingView(rootView: KeystrokeOverlayHUD(model: model))
    private lazy var panel = makePanel()

    private var hideTask: Task<Void, Never>?
    private var currentConfiguration = KeystrokeOverlayConfiguration.default
    private var coordinator = KeystrokeOverlayPresentationCoordinator()
    /// True from the moment the panel is ordered in until the fade-out completes.
    private var isShowing = false

    var isPreviewActive: Bool {
        coordinator.isPreviewActive
    }

    func update(configuration: KeystrokeOverlayConfiguration) {
        currentConfiguration = configuration
        model.apply(configuration: configuration)
        if panel.isVisible {
            restoreVisiblePanel()
        }
    }

    func showEvent(text: String, configuration: KeystrokeOverlayConfiguration) {
        guard coordinator.allowsEventPresentation else { return }
        present(text: text, configuration: configuration, intent: .event)
    }

    func showPreview(text: String, configuration: KeystrokeOverlayConfiguration) {
        present(text: text, configuration: configuration, intent: .preview)
    }

    func dismissEventPresentationIfNeeded() {
        guard coordinator.stopCapture() == .hidePresentation else { return }
        hide(immediately: true)
    }

    func hide(immediately: Bool) {
        hideTask?.cancel()
        hideTask = nil
        isShowing = false
        coordinator.finishPresentation()

        if immediately {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                self.panel.orderOut(nil)
            }
        }
    }

    private func present(
        text: String,
        configuration: KeystrokeOverlayConfiguration,
        intent: KeystrokeOverlayPresentationCoordinator.Intent
    ) {
        hideTask?.cancel()
        currentConfiguration = configuration
        coordinator.begin(intent)
        model.apply(configuration: configuration)
        model.text = text

        if isShowing {
            restoreVisiblePanel()
        } else {
            showPanel()
        }

        scheduleHide(using: configuration)
    }

    private func showPanel() {
        isShowing = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        layoutPanel()

        animatePanelAlpha(to: 1, duration: 0.12)
    }

    private func restoreVisiblePanel() {
        panel.alphaValue = 1
        layoutPanel()
    }

    private func scheduleHide(using configuration: KeystrokeOverlayConfiguration) {
        hideTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: configuration.holdDuration.nanoseconds)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                self.animatePanelAlpha(to: 0, duration: configuration.fadeOutDuration)
            }

            try? await Task.sleep(nanoseconds: configuration.fadeOutDuration.nanoseconds)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                self.isShowing = false
                self.coordinator.finishPresentation()
                self.panel.orderOut(nil)
            }
        }
    }

    private func animatePanelAlpha(
        to alphaValue: CGFloat,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alphaValue
        }
    }

    private func layoutPanel() {
        hostingView.layoutSubtreeIfNeeded()

        let contentSize = hostingView.fittingSize
        panel.setContentSize(contentSize)

        guard let screen = targetScreen() else { return }

        let frame = screen.visibleFrame
        let verticalSpace = frame.height - contentSize.height
        let origin = CGPoint(
            x: frame.midX - (contentSize.width / 2),
            y: frame.minY + verticalSpace * currentConfiguration.verticalPosition
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
}

@Observable
@MainActor
private final class KeystrokeOverlayPresentationModel {
    var text = ""
    var fontSize = KeystrokeOverlayConfiguration.default.fontSize
    var foregroundColor = KeystrokeOverlayConfiguration.default.foregroundColor.color
    var backgroundColor = KeystrokeOverlayConfiguration.default.backgroundColor.color

    func apply(configuration: KeystrokeOverlayConfiguration) {
        fontSize = configuration.fontSize
        foregroundColor = configuration.foregroundColor.color
        backgroundColor = configuration.backgroundColor.color
    }
}

private struct KeystrokeOverlayHUD: View {
    @Bindable var model: KeystrokeOverlayPresentationModel

    var body: some View {
        Text(model.text)
            .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
            .tracking(max(0.8, model.fontSize * 0.025))
            .foregroundStyle(model.foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, max(18, model.fontSize * 0.48))
            .padding(.vertical, max(12, model.fontSize * 0.28))
            .background {
                RoundedRectangle(cornerRadius: max(18, model.fontSize * 0.42), style: .continuous)
                    .fill(model.backgroundColor)
            }
            .fixedSize()
            .padding(8)
    }
}

private func keystrokeOverlayEventTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<KeystrokeOverlayService>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let modifiers = KeyCombo.Modifiers(cgEventFlags: event.flags)

    Task { @MainActor in
        service.handleEvent(type: type, keyCode: keyCode, modifiers: modifiers)
    }

    return Unmanaged.passUnretained(event)
}

private extension KeyCombo.Modifiers {
    init(cgEventFlags flags: CGEventFlags) {
        var modifiers: KeyCombo.Modifiers = []

        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.function_)
        }

        self = modifiers
    }
}

private extension Double {
    var nanoseconds: UInt64 {
        UInt64(max(self, 0) * 1_000_000_000)
    }
}
