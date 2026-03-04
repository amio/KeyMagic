import Foundation
import Observation
import Sparkle

/// Manages application auto-updates via the Sparkle framework.
///
/// Wraps `SPUStandardUpdaterController` to provide a simple observable interface
/// for SwiftUI views. Sparkle handles all update checking, downloading, signature
/// verification, installation, and relaunch automatically.
@Observable
@MainActor
public final class UpdateService: @unchecked Sendable {

    // MARK: - Published State

    /// Whether the updater is currently able to check for updates.
    private(set) public var canCheckForUpdates = false

    /// The date of the last successful update check, if any.
    public var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    /// Whether automatic update checks are enabled (backed by Sparkle's user defaults).
    public var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - Private

    private let updaterController: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    // MARK: - Init

    public init() {
        // Start the updater immediately; Sparkle defers its first check
        // until the second app launch by default (configurable via Info.plist).
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe Sparkle's KVO-compliant `canCheckForUpdates` property
        // and mirror it into our @Observable state.
        observation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            // SPUUpdater posts KVO on the main thread
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    // MARK: - Public API

    /// Trigger a user-initiated check for updates.
    /// Sparkle will display its own UI for progress, release notes, and installation.
    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}