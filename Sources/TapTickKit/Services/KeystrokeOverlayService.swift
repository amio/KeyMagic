import AppKit
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

        startCaptureIfNeeded()
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
        case .flagsChanged, .keyDown:
            guard configuration.isEnabled else { return }
            guard let text = overlayText(for: type, keyCode: keyCode, modifiers: modifiers) else { return }
            presenter.show(text: text, configuration: configuration)
        default:
            break
        }
    }

    private func overlayText(
        for eventType: CGEventType,
        keyCode: UInt32,
        modifiers: KeyCombo.Modifiers
    ) -> String? {
        switch eventType {
        case .flagsChanged:
            return modifiers.isEmpty ? nil : modifiers.displayString
        case .keyDown:
            let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
            guard combo != configuration.hotkey else { return nil }
            return combo.displayString
        default:
            return nil
        }
    }
}

@MainActor
private final class KeystrokeOverlayPresenter {
    private let model = KeystrokeOverlayPresentationModel()
    private lazy var hostingView = NSHostingView(rootView: KeystrokeOverlayHUD(model: model))
    private lazy var panel = makePanel()

    private var hideTask: Task<Void, Never>?

    func update(configuration: KeystrokeOverlayConfiguration) {
        model.apply(configuration: configuration)
        if panel.isVisible {
            layoutPanel()
        }
    }

    func show(text: String, configuration: KeystrokeOverlayConfiguration) {
        hideTask?.cancel()
        model.apply(configuration: configuration)
        model.text = text

        if panel.isVisible == false {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        layoutPanel()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
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
                self.panel.orderOut(nil)
            }
        }
    }

    func hide(immediately: Bool) {
        hideTask?.cancel()
        hideTask = nil

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
        let origin = CGPoint(
            x: frame.midX - (contentSize.width / 2),
            y: frame.minY + 56
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
