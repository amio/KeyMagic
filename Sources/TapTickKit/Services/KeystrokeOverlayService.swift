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

    private var configuration = KeystrokeOverlayConfiguration.default
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// After a combo keyDown, suppress flagsChanged until all modifiers are released.
    private var suppressFlagsUntilRelease = false
    /// Accumulated bare characters for consecutive typing (e.g. "HELLO").
    private var accumulatedText: String?
    /// Timestamp of the last presenter.show() call, used as the merge-window reference.
    private var lastShowTimestamp: CFAbsoluteTime = 0

    func refreshPermissionStatus() -> EventListeningPermissionStatus {
        notifyPermissionStatus(currentPermissionStatus())
    }

    func requestPermission() -> EventListeningPermissionStatus {
        if CGPreflightListenEventAccess() {
            return notifyPermissionStatus(.granted)
        }

        let granted = CGRequestListenEventAccess()
        return notifyPermissionStatus(granted ? .granted : .denied)
    }

    /// Show a transient preview HUD using the given configuration. Works regardless
    /// of whether the overlay is enabled — used by the settings UI for live feedback
    /// on position and timing changes.
    func showPreview(configuration: KeystrokeOverlayConfiguration) {
        presenter.show(text: configuration.hotkey.displayString, configuration: configuration)
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
            presenter.show(text: "Keystroke Overlay On", configuration: configuration)
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
        presenter.hide(immediately: true)
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
        CGPreflightListenEventAccess() ? .granted : .denied
    }

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

        // After a combo keyDown, suppress all flagsChanged until full release
        if suppressFlagsUntilRelease {
            if modifiers.isEmpty {
                suppressFlagsUntilRelease = false
            }
            return
        }

        guard !modifiers.isEmpty else { return }
        presenter.show(text: modifiers.displayString, configuration: configuration)
    }

    private func handleKeyDown(keyCode: UInt32, modifiers: KeyCombo.Modifiers) {
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard combo != configuration.hotkey else { return }

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
                presenter.show(text: accumulatedText!, configuration: configuration)
            } else {
                // Non-typeable key (Return, arrows, function keys …) — show standalone
                let keyName = KeyCodeMapping.keyName(for: keyCode)
                accumulatedText = nil
                lastShowTimestamp = CFAbsoluteTimeGetCurrent()
                presenter.show(text: keyName, configuration: configuration)
            }
        } else {
            // Combo with modifiers — show and arm suppression
            accumulatedText = nil
            suppressFlagsUntilRelease = true
            lastShowTimestamp = CFAbsoluteTimeGetCurrent()
            presenter.show(text: combo.displayString, configuration: configuration)
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

@MainActor
private final class KeystrokeOverlayPresenter {
    private let model = KeystrokeOverlayPresentationModel()
    private lazy var hostingView = NSHostingView(rootView: KeystrokeOverlayHUD(model: model))
    private lazy var panel = makePanel()

    private var hideTask: Task<Void, Never>?
    private var currentConfiguration = KeystrokeOverlayConfiguration.default
    /// True from the moment the panel is ordered in until the fade-out completes.
    private var isShowing = false

    func update(configuration: KeystrokeOverlayConfiguration) {
        currentConfiguration = configuration
        model.apply(configuration: configuration)
        if panel.isVisible {
            layoutPanel()
        }
    }

    func show(text: String, configuration: KeystrokeOverlayConfiguration) {
        hideTask?.cancel()
        currentConfiguration = configuration
        model.apply(configuration: configuration)
        model.text = text

        if isShowing {
            // Already on screen — snap to full opacity (kills any in-progress
            // fade-out) and update content/position without a fade-in animation.
            panel.alphaValue = 1
            layoutPanel()
        } else {
            // Fresh appearance — fade in.
            isShowing = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            layoutPanel()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
        }

        hideTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: configuration.holdDuration.nanoseconds)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = configuration.fadeOutDuration
                    context.allowsImplicitAnimation = true
                    self.panel.animator().alphaValue = 0
                }
            }

            try? await Task.sleep(nanoseconds: configuration.fadeOutDuration.nanoseconds)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                self.isShowing = false
                self.panel.orderOut(nil)
            }
        }
    }

    func hide(immediately: Bool) {
        hideTask?.cancel()
        hideTask = nil
        isShowing = false

        if immediately {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                self.panel.orderOut(nil)
            }
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
