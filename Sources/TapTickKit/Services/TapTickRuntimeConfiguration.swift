import Foundation

struct TapTickRuntimeConfiguration {
    let bundleIdentifier: String
    let displayName: String
    let appSupportDirectoryName: String

    init(bundle: Bundle = .main) {
        bundleIdentifier = bundle.bundleIdentifier ?? "com.taptick.app"
        displayName =
            Self.infoString("CFBundleDisplayName", bundle: bundle)
            ?? Self.infoString("CFBundleName", bundle: bundle)
            ?? "TapTick"
        appSupportDirectoryName =
            Self.infoString("TapTickAppSupportDirectoryName", bundle: bundle)
            ?? "TapTick"
    }

    private static func infoString(_ key: String, bundle: Bundle) -> String? {
        bundle.object(forInfoDictionaryKey: key) as? String
    }
}

extension TapTickRuntimeConfiguration {
    static let current = TapTickRuntimeConfiguration()
}
