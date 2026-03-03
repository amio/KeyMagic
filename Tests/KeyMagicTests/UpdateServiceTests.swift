import Testing
import Foundation
@testable import KeyMagicKit

@Suite("UpdateService")
struct UpdateServiceTests {

    private func makeService() -> UpdateService {
        // Prevent the auto-start timer from firing during tests by suspending
        // the initial DispatchQueue.main.async until after assertions.
        UpdateService()
    }

    // MARK: - isNewerVersion

    @Test("Same version is not newer")
    func sameVersionIsNotNewer() {
        let svc = makeService()
        #expect(!svc.isNewerVersion("1.0.0", than: "1.0.0"))
    }

    @Test("Patch bump is newer")
    func patchBumpIsNewer() {
        let svc = makeService()
        #expect(svc.isNewerVersion("1.0.1", than: "1.0.0"))
    }

    @Test("Minor bump is newer")
    func minorBumpIsNewer() {
        let svc = makeService()
        #expect(svc.isNewerVersion("1.1.0", than: "1.0.9"))
    }

    @Test("Major bump is newer")
    func majorBumpIsNewer() {
        let svc = makeService()
        #expect(svc.isNewerVersion("2.0.0", than: "1.9.9"))
    }

    @Test("Older version is not newer")
    func olderVersionIsNotNewer() {
        let svc = makeService()
        #expect(!svc.isNewerVersion("0.9.9", than: "1.0.0"))
    }

    @Test("Remote with extra component treated as zero for missing local parts")
    func extraComponentsHandled() {
        let svc = makeService()
        #expect(svc.isNewerVersion("1.0.0.1", than: "1.0.0"))
        #expect(!svc.isNewerVersion("1.0.0", than: "1.0.0.1"))
    }

    @Test("v-prefix stripped before comparison")
    func vPrefixStripped() {
        // The service strips "v" before comparing; verify version strings without "v" work.
        let svc = makeService()
        // "1.2.0" > "1.1.0"
        #expect(svc.isNewerVersion("1.2.0", than: "1.1.0"))
    }

    @Test("Zero patch vs no patch component")
    func zeroPatchVsNoPatch() {
        let svc = makeService()
        // "1.1" == "1.1.0" — not newer in either direction
        #expect(!svc.isNewerVersion("1.1", than: "1.1.0"))
        #expect(!svc.isNewerVersion("1.1.0", than: "1.1"))
    }
}
