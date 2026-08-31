import Testing
@testable import TapTickKit

@Suite("ScriptShebang")
struct ScriptShebangTests {
    @Test("Recognizes direct and env shell interpreters")
    func recognizesShells() {
        #expect(
            ScriptShebang.inspect("#!/bin/zsh\necho hi").shebang?.dialect == .zsh
        )
        #expect(
            ScriptShebang.inspect("#!/usr/bin/env sh\necho hi").shebang?.dialect == .sh
        )
        #expect(
            ScriptShebang.inspect("#!/usr/bin/env -S sh -e\necho hi").shebang?.dialect == .sh
        )
    }

    @Test("Distinguishes missing, malformed, and unavailable shebangs")
    func invalidStates() {
        #expect(ScriptShebang.inspect("echo hi") == .missing)
        #expect(
            ScriptShebang.inspect("#!zsh\necho hi")
                == .malformed("The shebang interpreter must use an absolute path")
        )
        #expect(
            ScriptShebang.inspect("#!/definitely/missing/interpreter\n")
                == .unavailable("/definitely/missing/interpreter")
        )
    }

    @Test("Applying a preset inserts or replaces exactly the first line")
    func appliesPreset() {
        #expect(
            ScriptShebang.replacingShebang(in: "echo hi", with: "#!/bin/zsh")
                == "#!/bin/zsh\n\necho hi"
        )
        #expect(
            ScriptShebang.replacingShebang(
                in: "#!/missing/runtime\necho hi",
                with: "#!/bin/bash"
            ) == "#!/bin/bash\necho hi"
        )
    }
}
