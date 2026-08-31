import Foundation
import Testing
@testable import TapTickKit

@Suite("Menu Bar Text")
struct MenuBarTextControllerTests {
    @Test("Defaults to no slots and persists ordered per-line configuration")
    @MainActor
    func persistsOrderedConfiguration() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let controller = MenuBarTextController(store: store, directory: directory)
        #expect(controller.slots.isEmpty)

        controller.addSlot()
        controller.addSlot()

        #expect(controller.slots[0].layout == .singleLine)
        #expect(controller.slots[0].alignment == .center)
        #expect(!controller.slots[0].fitsContentWidth)
        #expect(controller.slots[0].widthPoints == 50)
        #expect(controller.slots[0].topLine.scriptID == nil)
        #expect(controller.slots[0].bottomLine.scriptID == nil)
        #expect(controller.slots[0].topLine.refreshIntervalSeconds == 3)
        #expect(controller.renderedSlots.isEmpty)
        #expect(controller.previewSlots[0].widthPoints == 50)
        #expect(!controller.previewSlots[0].fitsContentWidth)
        #expect(controller.previewSlots[0].alignment == .center)
        #expect(controller.previewSlots[0].contents == [.chooseScript])

        let firstID = controller.slots[0].id
        let secondID = controller.slots[1].id
        let topScriptID = UUID()
        let bottomScriptID = UUID()

        controller.updateSlot(id: firstID) { slot in
            slot.layout = .twoLines
            slot.alignment = .right
            slot.fitsContentWidth = true
            slot.widthPoints = 88
            slot.topLine = MenuBarTextLineConfiguration(
                scriptID: topScriptID,
                refreshIntervalSeconds: 15
            )
            slot.bottomLine = MenuBarTextLineConfiguration(
                scriptID: bottomScriptID,
                refreshIntervalSeconds: 30
            )
        }
        #expect(controller.renderedSlots[0].alignment == .right)
        #expect(controller.renderedSlots[0].fitsContentWidth)
        #expect(controller.renderedSlots[0].widthPoints == 88)
        #expect(controller.renderedSlots[0].contents == [.loading, .loading])
        #expect(controller.renderedSlots[0].collapsesWhenEmpty)
        #expect(!controller.previewSlots[0].collapsesWhenEmpty)
        controller.moveSlot(id: secondID, offset: -1)

        let reloaded = MenuBarTextController(store: store, directory: directory)
        #expect(reloaded.slots.map(\.id) == [secondID, firstID])
        #expect(reloaded.slots[1].layout == .twoLines)
        #expect(reloaded.slots[1].alignment == .right)
        #expect(reloaded.slots[1].fitsContentWidth)
        #expect(reloaded.slots[1].widthPoints == 88)
        #expect(reloaded.slots[1].topLine.scriptID == topScriptID)
        #expect(reloaded.slots[1].topLine.refreshIntervalSeconds == 15)
        #expect(reloaded.slots[1].bottomLine.scriptID == bottomScriptID)
        #expect(reloaded.slots[1].bottomLine.refreshIntervalSeconds == 30)
    }

    @Test("Clamps slot width and each line refresh interval")
    @MainActor
    func clampsRefreshIntervals() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let controller = MenuBarTextController(store: store, directory: directory)
        controller.addSlot()

        controller.updateSlot(id: controller.slots[0].id) { slot in
            slot.widthPoints = 10
            slot.topLine.refreshIntervalSeconds = 0
            slot.bottomLine.refreshIntervalSeconds = 5000
        }

        #expect(controller.slots[0].widthPoints == 24)
        #expect(controller.slots[0].topLine.refreshIntervalSeconds == 1)
        #expect(controller.slots[0].bottomLine.refreshIntervalSeconds == 3600)
    }

    @Test("Reports scripts referenced by persisted menu bar lines")
    @MainActor
    func reportsReferencedScripts() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let controller = MenuBarTextController(store: store, directory: directory)
        let topScriptID = UUID()
        let bottomScriptID = UUID()
        let slotID = controller.addSlot()

        controller.updateSlot(id: slotID) { slot in
            slot.topLine.scriptID = topScriptID
            slot.bottomLine.scriptID = bottomScriptID
        }

        #expect(controller.usesScript(id: topScriptID))
        #expect(controller.usesScript(id: bottomScriptID))
        #expect(!controller.usesScript(id: UUID()))

        controller.removeSlot(id: slotID)

        #expect(!controller.usesScript(id: topScriptID))
        #expect(!controller.usesScript(id: bottomScriptID))
    }

    @Test("Migrates the previous single-script slot schema into the top line")
    @MainActor
    func migratesLegacySlot() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let slotID = UUID()
        let scriptID = UUID()
        let store = ShortcutStore(directory: directory)
        try writeConfiguration(
            """
            {
              "slots": [{
                "id": "\(slotID.uuidString)",
                "scriptID": "\(scriptID.uuidString)",
                "lineCount": 2,
                "refreshIntervalSeconds": 15
              }]
            }
            """,
            to: directory
        )

        let slot = try #require(MenuBarTextController(store: store, directory: directory).slots.first)

        #expect(slot.layout == .twoLines)
        #expect(slot.alignment == .center)
        #expect(!slot.fitsContentWidth)
        #expect(slot.widthPoints == 50)
        #expect(slot.topLine.scriptID == scriptID)
        #expect(slot.topLine.refreshIntervalSeconds == 15)
        #expect(slot.bottomLine.scriptID == nil)
        #expect(slot.bottomLine.refreshIntervalSeconds == 3)
    }

    @Test("Defaults width when migrating the previous per-line slot schema")
    @MainActor
    func migratesSlotWithoutWidth() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let slotID = UUID()
        let store = ShortcutStore(directory: directory)
        try writeConfiguration(
            """
            {
              "slots": [{
                "id": "\(slotID.uuidString)",
                "layout": "singleLine",
                "topLine": { "refreshIntervalSeconds": 3 },
                "bottomLine": { "refreshIntervalSeconds": 3 }
              }]
            }
            """,
            to: directory
        )

        let slot = try #require(MenuBarTextController(store: store, directory: directory).slots.first)

        #expect(slot.alignment == .center)
        #expect(!slot.fitsContentWidth)
        #expect(slot.widthPoints == 50)
    }

    @Test("Normalizes multiline output into one menu bar row")
    func normalizesScriptOutput() {
        let result = ScriptExecutionResult(
            output: "  CPU   12%\nMemory\t3 GB\nDisk 40%  ",
            exitCode: 0
        )

        #expect(MenuBarTextContent.scriptResult(result).text == "CPU 12% Memory 3 GB Disk 40%")
    }

    @Test("Uses empty success as a collapse signal while preserving failures")
    func usesCompactFallbacks() {
        let emptySuccess = ScriptExecutionResult(output: " \n", exitCode: 0)
        let emptyFailure = ScriptExecutionResult(output: "", exitCode: 7)

        #expect(MenuBarTextContent.scriptResult(emptySuccess) == .empty)
        #expect(MenuBarTextContent.scriptResult(emptyFailure).text == "Error (7)")
    }

    @Test("Starts both configured lines immediately")
    @MainActor
    func startsConfiguredLinesImmediately() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let top = Shortcut(name: "Top", action: .runScript(script: "top"))
        let bottom = Shortcut(name: "Bottom", action: .runScript(script: "bottom"))
        store.add(top)
        store.add(bottom)

        let runner = ControlledScriptRunner()
        let controller = MenuBarTextController(
            store: store,
            directory: directory,
            scriptRunner: ScriptRunner { command in await runner.run(command) },
            publicationInterval: .milliseconds(10)
        )
        let slotID = controller.addSlot()
        controller.updateSlot(id: slotID) { slot in
            slot.layout = .twoLines
            slot.topLine = MenuBarTextLineConfiguration(
                scriptID: top.id,
                refreshIntervalSeconds: 3600
            )
            slot.bottomLine = MenuBarTextLineConfiguration(
                scriptID: bottom.id,
                refreshIntervalSeconds: 3600
            )
        }

        controller.bootstrap()
        try await waitUntil { await runner.runCount == 2 }

        let actions = await runner.actions
        #expect(
            Set(actions)
                == Set([store.scriptCommand(for: top.id), store.scriptCommand(for: bottom.id)].compactMap { $0 })
        )
    }

    @Test("Publishes completed line results together on the shared cadence")
    @MainActor
    func publishesCompletedResultsTogether() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let top = Shortcut(name: "Top", action: .runScript(script: "top"))
        let bottom = Shortcut(name: "Bottom", action: .runScript(script: "bottom"))
        store.add(top)
        store.add(bottom)

        let runner = ControlledScriptRunner()
        let controller = MenuBarTextController(
            store: store,
            directory: directory,
            scriptRunner: ScriptRunner { command in await runner.run(command) },
            publicationInterval: .milliseconds(500)
        )
        let slotID = controller.addSlot()
        controller.updateSlot(id: slotID) { slot in
            slot.layout = .twoLines
            slot.topLine.scriptID = top.id
            slot.bottomLine.scriptID = bottom.id
        }

        controller.bootstrap()
        try await waitUntil { await runner.runCount == 2 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(controller.renderedSlots.first?.contents == [.loading, .loading])

        try await waitUntil {
            controller.renderedSlots.first?.contents.map(\.text) == ["top", "bottom"]
        }
    }

    @Test("Serializes bottom-line reactivation during execution")
    @MainActor
    func serializesBottomLineReactivation() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let first = Shortcut(name: "First", action: .runScript(script: "first"))
        let second = Shortcut(name: "Second", action: .runScript(script: "second"))
        store.add(first)
        store.add(second)

        let runner = ControlledScriptRunner(blocksFirstRun: true)
        let controller = MenuBarTextController(
            store: store,
            directory: directory,
            scriptRunner: ScriptRunner { command in await runner.run(command) },
            publicationInterval: .milliseconds(10)
        )
        let slotID = controller.addSlot()
        controller.updateSlot(id: slotID) { slot in
            slot.layout = .twoLines
            slot.bottomLine = MenuBarTextLineConfiguration(
                scriptID: first.id,
                refreshIntervalSeconds: 3600
            )
        }
        controller.bootstrap()
        try await waitUntil { await runner.runCount == 1 }

        controller.updateSlot(id: slotID) { $0.layout = .singleLine }
        controller.updateSlot(id: slotID) { $0.bottomLine.scriptID = second.id }
        controller.updateSlot(id: slotID) { $0.layout = .twoLines }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await runner.runCount == 1)

        await runner.releaseFirstRun()
        try await waitUntil { await runner.runCount == 2 }

        let snapshot = await runner.snapshot()
        #expect(
            snapshot.actions
                == [store.scriptCommand(for: first.id), store.scriptCommand(for: second.id)].compactMap { $0 }
        )
        #expect(snapshot.maximumConcurrentRuns == 1)
        try await waitUntil { controller.renderedSlots.first?.contents.last?.text == "second" }
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickMenuBarText-\(UUID().uuidString)")
    }

    private func writeConfiguration(_ json: String, to directory: URL) throws {
        let data = try #require(json.data(using: .utf8))
        try data.write(to: directory.appendingPathComponent("menu-bar-text.json"))
    }
}

private actor ControlledScriptRunner {
    private(set) var actions: [ScriptCommand] = []
    private(set) var maximumConcurrentRuns = 0

    private let blocksFirstRun: Bool
    private var activeRunCount = 0
    private var firstRunContinuation: CheckedContinuation<Void, Never>?

    init(blocksFirstRun: Bool = false) {
        self.blocksFirstRun = blocksFirstRun
    }

    var runCount: Int {
        actions.count
    }

    func run(_ command: ScriptCommand) async -> ScriptExecutionResult {
        actions.append(command)
        activeRunCount += 1
        maximumConcurrentRuns = max(maximumConcurrentRuns, activeRunCount)

        if blocksFirstRun, actions.count == 1 {
            await withCheckedContinuation { firstRunContinuation = $0 }
        }

        activeRunCount -= 1
        return ScriptExecutionResult(output: output(for: command), exitCode: 0)
    }

    func releaseFirstRun() {
        let continuation = firstRunContinuation
        firstRunContinuation = nil
        continuation?.resume()
    }

    func snapshot() -> (actions: [ScriptCommand], maximumConcurrentRuns: Int) {
        (actions, maximumConcurrentRuns)
    }

    private func output(for command: ScriptCommand) -> String {
        (try? String(contentsOf: command.fileURL, encoding: .utf8)) ?? ""
    }
}

private enum MenuBarTextTestError: Error {
    case timedOut
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor @Sendable () async -> Bool
) async throws {
    for _ in 0..<200 {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw MenuBarTextTestError.timedOut
}
