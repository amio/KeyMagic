import AppKit
import Foundation
import Observation
import os.log

/// Checks GitHub Releases for newer versions and manages download + in-place installation.
///
/// On first creation the service schedules a periodic check every 24 hours.
/// When a newer version is found, `updateAvailable` is set to `true`.
/// Calling `downloadAndInstall()` will:
///   1. Download the latest release DMG to a temp directory.
///   2. Mount the DMG with `hdiutil`.
///   3. Copy `KeyMagic.app` over the currently running copy.
///   4. Spawn a background shell that reopens the app once this process exits.
///   5. Quit the running process via `NSApp.terminate`.
@Observable
public final class UpdateService: @unchecked Sendable {

    // MARK: - Published State

    private(set) public var isChecking = false
    private(set) public var updateAvailable = false
    private(set) public var latestVersion = ""
    private(set) public var isDownloading = false
    private(set) public var downloadProgress: Double = 0
    private(set) public var errorMessage: String?

    // MARK: - Config

    static let repoOwner = "amio"
    static let repoName  = "KeyMagic"
    static let apiURL    = URL(string: "https://api.github.com/repos/amio/KeyMagic/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60  // 24 hours
    static let apiVersion = "2022-11-28"

    // MARK: - Private

    private let logger = Logger(subsystem: "com.keymagic.app", category: "Update")
    private var checkTimer: Timer?
    private var dmgDownloadURL: URL?

    public init() {
        // Defer the first check until after the app has fully launched.
        DispatchQueue.main.async { [weak self] in
            self?.startPeriodicChecks()
        }
    }

    // MARK: - Public API

    /// Start periodic version checks (idempotent — safe to call more than once).
    /// Fires once immediately, then every 24 hours.
    public func startPeriodicChecks() {
        guard checkTimer == nil else { return }
        Task { await checkForUpdates() }
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: Self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { await self?.checkForUpdates() }
        }
    }

    /// One-shot check against the GitHub Releases API.
    @MainActor
    public func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            let remote = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            guard isNewerVersion(remote, than: currentVersion()) else {
                logger.info("Already up to date (\(self.currentVersion()))")
                return
            }

            latestVersion = remote
            dmgDownloadURL = release.assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL
            updateAvailable = true
            logger.info("Update available: \(remote)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Update check failed: \(error)")
        }
    }

    /// Download the latest release DMG, install it over the running copy, then relaunch.
    @MainActor
    public func downloadAndInstall() async {
        guard let url = dmgDownloadURL, !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            let dmgURL = try await downloadDMG(from: url)
            // Run blocking hdiutil / FileManager work off the main thread.
            try await Task.detached(priority: .userInitiated) { [self] in
                try installFromDMG(at: dmgURL)
            }.value
            relaunchApp()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Install failed: \(error)")
            isDownloading = false
        }
    }

    // MARK: - Version Helpers (internal for testing)

    func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Returns `true` when `remote` is strictly greater than `local`
    /// using element-wise semantic version comparison.
    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let r = parseVersion(remote)
        let l = parseVersion(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false  // equal
    }

    private func parseVersion(_ v: String) -> [Int] {
        v.split(separator: ".").compactMap { Int($0) }
    }

    // MARK: - GitHub API

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Download

    @MainActor
    private func downloadDMG(from url: URL) async throws -> URL {
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyMagicUpdate", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        downloadProgress = 1
        return destURL
    }

    // MARK: - Install

    private func installFromDMG(at dmgURL: URL) throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyMagicMount-\(UUID().uuidString)", isDirectory: true)

        // Attach the DMG.
        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else { throw UpdateError.mountFailed }

        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-quiet"]
            try? detach.run()
            detach.waitUntilExit()
        }

        let sourceApp = mountPoint.appendingPathComponent("KeyMagic.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw UpdateError.appNotFoundInDMG
        }

        // Atomically replace the running copy to avoid a window where the app
        // is deleted but the new version hasn't been written yet.
        let currentAppURL = Bundle.main.bundleURL
        var resultURL: NSURL?
        try FileManager.default.replaceItem(
            at: currentAppURL,
            withItemAt: sourceApp,
            backupItemName: "KeyMagic.app.bak",
            resultingItemURL: &resultURL
        )
        logger.info("Installed update to \(currentAppURL.path)")
    }

    // MARK: - Relaunch

    private func relaunchApp() {
        // Escape single quotes in the path so it's safe to wrap with single quotes in the shell.
        let appPath = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let pid     = ProcessInfo.processInfo.processIdentifier

        // A background shell waits for the current process to exit, then reopens the app.
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open '\(appPath)'"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()

        NSApp.terminate(nil)
    }

    // MARK: - Errors

    enum UpdateError: LocalizedError {
        case mountFailed
        case appNotFoundInDMG

        var errorDescription: String? {
            switch self {
            case .mountFailed:       return "Failed to mount the update disk image."
            case .appNotFoundInDMG: return "KeyMagic.app was not found in the disk image."
            }
        }
    }
}
