import Foundation
import Observation

@Observable
@MainActor
public final class UtilitiesController: @unchecked Sendable {
    public init(directory: URL? = nil) {
        let baseDirectory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("TapTick", isDirectory: true)

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let fileURL = baseDirectory.appendingPathComponent("utilities.json")
        let loadedConfig = Self.loadConfiguration(from: fileURL) ?? .default

        // Phase 1: initialize all stored properties before touching self.
        self.fileURL = fileURL
        self.catalog = UtilityDescriptor.catalog
        self.configuration = loadedConfig
        self.keystrokeOverlayService = KeystrokeOverlayService()
        self.keystrokeOverlayPermission = .unknown
        self.isKeystrokeOverlayCapturing = false

        let screenshotService = ScreenshotService()
        screenshotService.lastAnnotationMode = loadedConfig.screenshotTools.lastAnnotationMode
        screenshotService.lastAnnotationColorIndex = loadedConfig.screenshotTools.lastAnnotationColorIndex
        self.screenshotService = screenshotService

        // Phase 2: all stored properties initialized — safe to capture self.
        keystrokeOverlayService.onPermissionChange = { [weak self] status in
            self?.keystrokeOverlayPermission = status
        }
        keystrokeOverlayService.onCaptureStateChange = { [weak self] isCapturing in
            self?.isKeystrokeOverlayCapturing = isCapturing
        }
        screenshotService.onAnnotationSettingsChanged = { [weak self] mode, colorIndex in
            self?.screenshotTools.lastAnnotationMode = mode
            self?.screenshotTools.lastAnnotationColorIndex = colorIndex
        }
    }

    let catalog: [UtilityDescriptor]

    private var configuration: UtilityConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            saveConfiguration()
            applyKeystrokeOverlayConfiguration(promptForPermission: false)
        }
    }

    private let fileURL: URL
    private let keystrokeOverlayService: KeystrokeOverlayService
    private let screenshotService: ScreenshotService

    private(set) var keystrokeOverlayPermission: EventListeningPermissionStatus
    private(set) var isKeystrokeOverlayCapturing: Bool

    public var onReservedHotkeysChanged: (() -> Void)?

    var keystrokeOverlay: KeystrokeOverlayConfiguration {
        get { configuration.keystrokeOverlay }
        set { configuration.keystrokeOverlay = newValue }
    }

    var screenshotTools: ScreenshotToolsConfiguration {
        get { configuration.screenshotTools }
        set { configuration.screenshotTools = newValue }
    }

    /// Refresh the on-screen preview HUD using the current settings configuration.
    /// Repeated calls are expected while the user tunes settings, so the underlying
    /// presenter should keep the preview alive instead of flashing between updates.
    func showKeystrokeOverlayPreview() {
        keystrokeOverlayService.showPreview(configuration: keystrokeOverlay)
    }

    public func bootstrap() {
        keystrokeOverlayPermission = keystrokeOverlayService.refreshPermissionStatus()
        applyKeystrokeOverlayConfiguration(promptForPermission: false)
    }

    func descriptor(for featureID: UtilityID) -> UtilityDescriptor {
        catalog.first(where: { $0.id == featureID }) ?? catalog[0]
    }

    func reservedHotkeys() -> [(featureID: UtilityID, action: String, combo: KeyCombo)] {
        var hotkeys: [(featureID: UtilityID, action: String, combo: KeyCombo)] = [
            (.keystrokeOverlay, "toggle", keystrokeOverlay.hotkey),
        ]
        if screenshotTools.isEnabled {
            hotkeys.append((.screenshotTools, "captureClipboard", screenshotTools.captureToClipboardHotkey))
            hotkeys.append((.screenshotTools, "captureAndMark", screenshotTools.captureAndMarkHotkey))
        }
        return hotkeys
    }

    func reservedHotkeyConflict(for combo: KeyCombo, excluding featureID: UtilityID? = nil) -> Bool {
        reservedHotkeys().contains { entry in
            entry.featureID != featureID && entry.combo == combo
        }
    }

    func updateKeystrokeOverlayHotkey(_ combo: KeyCombo) {
        guard keystrokeOverlay.hotkey != combo else { return }
        keystrokeOverlay.hotkey = combo
        onReservedHotkeysChanged?()
    }

    func restoreDefaultKeystrokeOverlayHotkey() {
        updateKeystrokeOverlayHotkey(KeystrokeOverlayConfiguration.defaultHotkey)
    }

    // MARK: - Screenshot Tools

    func setScreenshotToolsEnabled(_ isEnabled: Bool) {
        screenshotTools.isEnabled = isEnabled
        onReservedHotkeysChanged?()
    }

    func updateScreenshotCaptureToClipboardHotkey(_ combo: KeyCombo) {
        guard screenshotTools.captureToClipboardHotkey != combo else { return }
        screenshotTools.captureToClipboardHotkey = combo
        onReservedHotkeysChanged?()
    }

    func updateScreenshotCaptureAndMarkHotkey(_ combo: KeyCombo) {
        guard screenshotTools.captureAndMarkHotkey != combo else { return }
        screenshotTools.captureAndMarkHotkey = combo
        onReservedHotkeysChanged?()
    }

    func restoreDefaultScreenshotHotkeys() {
        updateScreenshotCaptureToClipboardHotkey(ScreenshotToolsConfiguration.defaultCaptureToClipboardHotkey)
        updateScreenshotCaptureAndMarkHotkey(ScreenshotToolsConfiguration.defaultCaptureAndMarkHotkey)
    }

    func requestKeystrokeOverlayPermission() {
        keystrokeOverlayPermission = keystrokeOverlayService.requestPermission()
        if keystrokeOverlay.isEnabled {
            applyKeystrokeOverlayConfiguration(promptForPermission: false)
        }
    }

    func setKeystrokeOverlayEnabled(_ isEnabled: Bool, promptForPermission: Bool = true) {
        guard isEnabled else {
            keystrokeOverlay.isEnabled = false
            return
        }

        let permission = promptForPermission
            ? keystrokeOverlayService.requestPermission()
            : keystrokeOverlayService.refreshPermissionStatus()

        keystrokeOverlayPermission = permission

        guard permission == .granted else {
            keystrokeOverlay.isEnabled = false
            return
        }

        keystrokeOverlay.isEnabled = true
    }

    func toggleFeature(_ featureID: UtilityID) {
        switch featureID {
        case .keystrokeOverlay:
            setKeystrokeOverlayEnabled(!keystrokeOverlay.isEnabled)
        case .screenshotTools:
            setScreenshotToolsEnabled(!screenshotTools.isEnabled)
        case .windowManager, .largeType:
            break
        }
    }

    func handleHotkey(for featureID: UtilityID, action: String) {
        switch featureID {
        case .keystrokeOverlay:
            toggleFeature(featureID)
        case .screenshotTools:
            guard screenshotTools.isEnabled else { return }
            switch action {
            case "captureClipboard":
                screenshotService.captureToClipboard()
            case "captureAndMark":
                screenshotService.captureAndMark()
            default:
                break
            }
        case .windowManager, .largeType:
            break
        }
    }

    private func applyKeystrokeOverlayConfiguration(promptForPermission: Bool) {
        keystrokeOverlayPermission = keystrokeOverlayService.apply(
            configuration: keystrokeOverlay,
            promptForPermission: promptForPermission
        )
    }

    private func saveConfiguration() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("TapTick: Failed to save utility configuration: \(error)")
        }
    }

    private static func loadConfiguration(from fileURL: URL) -> UtilityConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(UtilityConfiguration.self, from: data)
        } catch {
            print("TapTick: Failed to load utility configuration: \(error)")
            return nil
        }
    }
}