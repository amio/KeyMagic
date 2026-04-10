import Foundation
import Observation

@Observable
@MainActor
public final class BuiltInFeatureController: @unchecked Sendable {
    public init(directory: URL? = nil) {
        let baseDirectory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("TapTick", isDirectory: true)

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        self.fileURL = baseDirectory.appendingPathComponent("built-in-features.json")
        self.catalog = BuiltInFeatureDescriptor.catalog

        if let configuration = Self.loadConfiguration(from: self.fileURL) {
            self.configuration = configuration
        } else {
            self.configuration = .default
        }

        self.keystrokeOverlayService = KeystrokeOverlayService()
        self.keystrokeOverlayPermission = .unknown
        self.isKeystrokeOverlayCapturing = false

        keystrokeOverlayService.onPermissionChange = { [weak self] status in
            self?.keystrokeOverlayPermission = status
        }
        keystrokeOverlayService.onCaptureStateChange = { [weak self] isCapturing in
            self?.isKeystrokeOverlayCapturing = isCapturing
        }
    }

    let catalog: [BuiltInFeatureDescriptor]

    private var configuration: BuiltInFeatureConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            saveConfiguration()
            applyKeystrokeOverlayConfiguration(promptForPermission: false)
        }
    }

    private let fileURL: URL
    private let keystrokeOverlayService: KeystrokeOverlayService

    private(set) var keystrokeOverlayPermission: EventListeningPermissionStatus
    private(set) var isKeystrokeOverlayCapturing: Bool

    public var onReservedHotkeysChanged: (() -> Void)?

    var keystrokeOverlay: KeystrokeOverlayConfiguration {
        get { configuration.keystrokeOverlay }
        set { configuration.keystrokeOverlay = newValue }
    }

    /// Show a transient preview HUD on the actual screen, used by the settings UI
    /// for live feedback on position and timing changes.
    func showKeystrokeOverlayPreview() {
        keystrokeOverlayService.showPreview(configuration: keystrokeOverlay)
    }

    public func bootstrap() {
        keystrokeOverlayPermission = keystrokeOverlayService.refreshPermissionStatus()
        applyKeystrokeOverlayConfiguration(promptForPermission: false)
    }

    func descriptor(for featureID: BuiltInFeatureID) -> BuiltInFeatureDescriptor {
        catalog.first(where: { $0.id == featureID }) ?? catalog[0]
    }

    func reservedHotkeys() -> [(featureID: BuiltInFeatureID, combo: KeyCombo)] {
        [
            (.keystrokeOverlay, keystrokeOverlay.hotkey),
        ]
    }

    func reservedHotkeyConflict(for combo: KeyCombo, excluding featureID: BuiltInFeatureID? = nil) -> Bool {
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

    func toggleFeature(_ featureID: BuiltInFeatureID) {
        switch featureID {
        case .keystrokeOverlay:
            setKeystrokeOverlayEnabled(!keystrokeOverlay.isEnabled)
        case .screenshotTools, .windowManager, .largeType:
            break
        }
    }

    func handleHotkey(for featureID: BuiltInFeatureID) {
        toggleFeature(featureID)
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
            print("TapTick: Failed to save built-in feature configuration: \(error)")
        }
    }

    private static func loadConfiguration(from fileURL: URL) -> BuiltInFeatureConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(BuiltInFeatureConfiguration.self, from: data)
        } catch {
            print("TapTick: Failed to load built-in feature configuration: \(error)")
            return nil
        }
    }
}
