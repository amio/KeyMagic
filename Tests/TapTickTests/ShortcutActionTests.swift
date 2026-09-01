import Testing
import Foundation
@testable import TapTickKit

@Suite("ShortcutAction")
struct ShortcutActionTests {

    @Test("Launch app display description")
    func launchAppDescription() {
        let action = ShortcutAction.launchApp(
            bundleIdentifier: "com.apple.finder",
            appName: "Finder"
        )
        #expect(action.displayDescription == "Launch Finder")
    }

    @Test("Run script display description truncates")
    func runScriptDescriptionTruncates() {
        let longScript = String(repeating: "echo hello; ", count: 10)
        let action = ShortcutAction.runScript(script: "#!/bin/bash\n\n\(longScript)")
        #expect(action.displayDescription.contains("..."))
        #expect(action.displayDescription.hasPrefix("Script:"))
    }

    @Test("Run script file display description shows filename")
    func runScriptFileDescription() {
        let action = ShortcutAction.runScriptFile(
            path: "/Users/test/scripts/hello.sh",
            shell: .zsh
        )
        #expect(action.displayDescription == "Legacy script: hello.sh")
    }

    @Test("Codable round-trip for all variants")
    func codableRoundTrip() throws {
        let actions: [ShortcutAction] = [
            .launchApp(bundleIdentifier: "com.apple.safari", appName: "Safari"),
            .runScript(script: "#!/bin/zsh\necho hello"),
            .runScriptFile(path: "/test.sh", shell: .bash),
        ]

        for action in actions {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(ShortcutAction.self, from: data)
            #expect(decoded == action)
        }
    }

    @Test("Legacy inline action gains its selected shell as a shebang")
    func legacyInlineMigration() throws {
        let data = Data(#"{"runScript":{"script":"echo hi","shell":"/bin/bash"}}"#.utf8)
        let action = try JSONDecoder().decode(ShortcutAction.self, from: data)
        #expect(action == .runScript(script: "#!/bin/bash\n\necho hi"))
    }
}
