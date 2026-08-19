import Foundation

struct TapTickRuntimeConfiguration {
    let bundleIdentifier: String
    let displayName: String
    let appSupportDirectoryName: String
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        bundleIdentifier = bundle.bundleIdentifier ?? "com.taptick.app"
        displayName =
            Self.infoString("CFBundleDisplayName", bundle: bundle)
            ?? Self.infoString("CFBundleName", bundle: bundle)
            ?? "TapTick"
        appSupportDirectoryName =
            Self.infoString("TapTickAppSupportDirectoryName", bundle: bundle)
            ?? "TapTick"
        version =
            Self.infoString("CFBundleShortVersionString", bundle: bundle)
            ?? "1.0.0"
        build =
            Self.infoString("CFBundleVersion", bundle: bundle)
            ?? "1"
    }

    private static func infoString(_ key: String, bundle: Bundle) -> String? {
        bundle.object(forInfoDictionaryKey: key) as? String
    }
}

extension TapTickRuntimeConfiguration {
    static let current = TapTickRuntimeConfiguration()

    var versionLabel: String {
        version.hasSuffix("+b\(build)") ? version : "\(version) (\(build))"
    }
}
