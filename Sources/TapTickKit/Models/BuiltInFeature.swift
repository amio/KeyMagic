import AppKit
import Carbon.HIToolbox
import SwiftUI

enum BuiltInFeatureID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case keystrokeOverlay
    case screenshotTools
    case windowManager
    case largeType

    var id: String { rawValue }
}

enum BuiltInFeatureAvailability: String, Codable, Hashable, Sendable {
    case available
    case planned

    var badgeTitle: String {
        switch self {
        case .available:
            "Live"
        case .planned:
            "Planned"
        }
    }
}

struct BuiltInFeatureDescriptor: Identifiable, Hashable, Sendable {
    let id: BuiltInFeatureID
    let title: String
    let summary: String
    let systemImage: String
    let availability: BuiltInFeatureAvailability
    let highlights: [String]

    static let catalog: [BuiltInFeatureDescriptor] = [
        BuiltInFeatureDescriptor(
            id: .keystrokeOverlay,
            title: "Keystroke Overlay",
            summary: "Show the current key chord in a subtitle-style HUD near the bottom of the screen.",
            systemImage: "keyboard",
            availability: .available,
            highlights: [
                "Global toggle hotkey",
                "Subtitle-style floating overlay",
                "Font, color, hold time, and fade controls",
            ]
        ),
        BuiltInFeatureDescriptor(
            id: .screenshotTools,
            title: "Screenshot Tools",
            summary: "Capture screen regions, annotate quickly, and send the result straight to the clipboard.",
            systemImage: "camera.viewfinder",
            availability: .planned,
            highlights: [
                "Fast capture flow",
                "Quick mark-up actions",
                "Clipboard-first output",
            ]
        ),
        BuiltInFeatureDescriptor(
            id: .windowManager,
            title: "Window Manager",
            summary: "Resize, snap, and reposition windows with native layouts and shortcut-driven commands.",
            systemImage: "uiwindow.split.2x1",
            availability: .planned,
            highlights: [
                "Preset layouts",
                "Per-action hotkeys",
                "Native window geometry control",
            ]
        ),
        BuiltInFeatureDescriptor(
            id: .largeType,
            title: "Large Type",
            summary: "Project large temporary text on screen for quick glanceable display, similar to Alfred.",
            systemImage: "textformat.size.larger",
            availability: .planned,
            highlights: [
                "Huge readable text",
                "Transient overlay presentation",
                "Shortcut-triggered display",
            ]
        ),
    ]
}

enum EventListeningPermissionStatus: String, Codable, Hashable, Sendable {
    case unknown
    case granted
    case denied

    var title: String {
        switch self {
        case .unknown:
            "Unknown"
        case .granted:
            "Granted"
        case .denied:
            "Required"
        }
    }
}

struct RGBAColor: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(color.redComponent).nativeClamped,
            green: Double(color.greenComponent).nativeClamped,
            blue: Double(color.blueComponent).nativeClamped,
            alpha: Double(color.alphaComponent).nativeClamped
        )
    }

    var nsColor: NSColor {
        NSColor(
            red: red.nativeClamped,
            green: green.nativeClamped,
            blue: blue.nativeClamped,
            alpha: alpha.nativeClamped
        )
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

struct KeystrokeOverlayConfiguration: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var hotkey: KeyCombo
    var fontSize: Double
    var foregroundColor: RGBAColor
    var backgroundColor: RGBAColor
    var holdDuration: Double
    var fadeOutDuration: Double

    static let defaultHotkey = KeyCombo(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: [.command, .control, .option]
    )

    static let `default` = KeystrokeOverlayConfiguration(
        isEnabled: false,
        hotkey: defaultHotkey,
        fontSize: 34,
        foregroundColor: RGBAColor(NSColor.white),
        backgroundColor: RGBAColor(
            red: 0.05,
            green: 0.05,
            blue: 0.05,
            alpha: 0.84
        ),
        holdDuration: 1.3,
        fadeOutDuration: 0.28
    )
}

struct BuiltInFeatureConfiguration: Codable, Hashable, Sendable {
    var keystrokeOverlay: KeystrokeOverlayConfiguration

    static let `default` = BuiltInFeatureConfiguration(
        keystrokeOverlay: .default
    )
}

private extension Double {
    var nativeClamped: Double {
        min(max(self, 0), 1)
    }
}
