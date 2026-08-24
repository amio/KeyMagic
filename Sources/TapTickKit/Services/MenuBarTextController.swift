import Foundation
import Observation

/// Owns menu bar slot persistence, resolved content, and one serial worker per configured line.
@MainActor
@Observable
public final class MenuBarTextController {
    private(set) var slots: [MenuBarTextSlot]
    private var contentByLineKey: [MenuBarTextLineKey: MenuBarTextContent] = [:]

    @ObservationIgnored private let store: ShortcutStore
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let runScript: @Sendable (ShortcutAction) async -> ScriptExecutionResult
    @ObservationIgnored private var isBootstrapped = false
    @ObservationIgnored private var refreshJobs: [MenuBarTextLineKey: MenuBarTextRefreshJob] = [:]

    /** Configured slots rendered beside the icon in the shared menu bar button. */
    var renderedSlots: [MenuBarTextRenderedSlot] {
        slots.compactMap { slot in
            guard slot.hasActiveScript else { return nil }
            return renderedSlot(slot, showsPlaceholders: false)
        }
    }

    /** Every settings slot, including unbound lines that need a configuration affordance. */
    var previewSlots: [MenuBarTextRenderedSlot] {
        slots.map { renderedSlot($0, showsPlaceholders: true) }
    }

    public convenience init(store: ShortcutStore, directory: URL? = nil) {
        self.init(
            store: store,
            directory: directory,
            runScript: ShortcutExecutor.executeScript
        )
    }

    init(
        store: ShortcutStore,
        directory: URL? = nil,
        runScript: @escaping @Sendable (ShortcutAction) async -> ScriptExecutionResult
    ) {
        let baseDirectory =
            directory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent(
                TapTickRuntimeConfiguration.current.appSupportDirectoryName,
                isDirectory: true
            )

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let fileURL = baseDirectory.appendingPathComponent("menu-bar-text.json")
        self.store = store
        self.fileURL = fileURL
        self.runScript = runScript
        self.slots = Self.loadConfiguration(from: fileURL)?.slots ?? []
    }

    deinit {
        for job in refreshJobs.values {
            job.task.cancel()
        }
    }

    public func bootstrap() {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        reconcileRefreshJobs()
    }

    @discardableResult
    func addSlot() -> UUID {
        let slot = MenuBarTextSlot()
        slots.append(slot)
        configurationDidChange()
        return slot.id
    }

    func updateSlot(id: UUID, _ mutation: (inout MenuBarTextSlot) -> Void) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }

        var slot = slots[index]
        mutation(&slot)
        slot.normalize()
        guard slots[index] != slot else { return }

        slots[index] = slot
        configurationDidChange()
    }

    func removeSlot(id: UUID) {
        guard slots.contains(where: { $0.id == id }) else { return }
        slots.removeAll { $0.id == id }
        configurationDidChange()
    }

    func moveSlot(id: UUID, offset: Int) {
        guard let sourceIndex = slots.firstIndex(where: { $0.id == id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard slots.indices.contains(destinationIndex) else { return }

        let slot = slots.remove(at: sourceIndex)
        slots.insert(slot, at: destinationIndex)
        configurationDidChange()
    }

    private func renderedSlot(
        _ slot: MenuBarTextSlot,
        showsPlaceholders: Bool
    ) -> MenuBarTextRenderedSlot {
        let contents = slot.layout.activeLinePositions.map { position in
            guard slot[position].scriptID != nil else {
                return showsPlaceholders ? MenuBarTextContent.chooseScript : .empty
            }
            let lineKey = MenuBarTextLineKey(slotID: slot.id, position: position)
            return contentByLineKey[lineKey] ?? .loading
        }
        return MenuBarTextRenderedSlot(
            id: slot.id,
            alignment: slot.alignment,
            fitsContentWidth: slot.fitsContentWidth,
            widthPoints: slot.widthPoints,
            contents: contents,
            collapsesWhenEmpty: !showsPlaceholders
        )
    }

    private func configurationDidChange() {
        saveConfiguration()
        guard isBootstrapped else { return }
        reconcileRefreshJobs()
    }

    private func reconcileRefreshJobs() {
        let definitions = activeRefreshDefinitions()
        let activeLineKeys = Set(definitions.keys)
        let retainedSlotIDs = Set(slots.map(\.id))

        contentByLineKey = contentByLineKey.filter { activeLineKeys.contains($0.key) }

        let removedLineKeys = refreshJobs.keys.filter { !retainedSlotIDs.contains($0.slotID) }
        for lineKey in removedLineKeys {
            guard let job = refreshJobs.removeValue(forKey: lineKey) else { continue }
            job.state.stop()
            job.task.cancel()
        }

        for (lineKey, job) in refreshJobs {
            let definition = definitions[lineKey]
            guard job.state.definition != definition else { continue }
            job.state.update(definition: definition)
            if definition != nil, contentByLineKey[lineKey] == nil {
                contentByLineKey[lineKey] = .loading
            }
        }

        for (lineKey, definition) in definitions where refreshJobs[lineKey] == nil {
            contentByLineKey[lineKey] = contentByLineKey[lineKey] ?? .loading
            refreshJobs[lineKey] = makeRefreshJob(
                lineKey: lineKey,
                definition: definition
            )
        }
    }

    private func activeRefreshDefinitions() -> [MenuBarTextLineKey: MenuBarTextRefreshDefinition] {
        var definitions: [MenuBarTextLineKey: MenuBarTextRefreshDefinition] = [:]

        for slot in slots {
            for position in slot.layout.activeLinePositions {
                guard let scriptID = slot[position].scriptID else { continue }
                definitions[MenuBarTextLineKey(slotID: slot.id, position: position)] =
                    MenuBarTextRefreshDefinition(
                        scriptID: scriptID,
                        refreshIntervalSeconds: slot[position].refreshIntervalSeconds
                    )
            }
        }

        return definitions
    }

    private func makeRefreshJob(
        lineKey: MenuBarTextLineKey,
        definition: MenuBarTextRefreshDefinition
    ) -> MenuBarTextRefreshJob {
        let state = MenuBarTextRefreshState(
            lineKey: lineKey,
            definition: definition
        )
        let runScript = runScript
        let task = Task { [weak self, state, runScript] in
            while !Task.isCancelled, !state.isStopped {
                guard let definition = state.definition else {
                    await state.suspend(whileDefinitionIs: nil)
                    continue
                }
                guard self != nil else { return }

                let content: MenuBarTextContent
                if let action = self?.scriptAction(for: definition.scriptID) {
                    content = .scriptResult(await runScript(action))
                } else {
                    content = .unavailable
                }

                guard !Task.isCancelled, !state.isStopped else { return }
                guard state.definition == definition else { continue }
                guard self?.owns(state) == true else { return }

                self?.apply(content, to: lineKey)
                await state.suspend(
                    whileDefinitionIs: definition,
                    for: .seconds(definition.refreshIntervalSeconds)
                )
            }
        }
        return MenuBarTextRefreshJob(state: state, task: task)
    }

    private func owns(_ state: MenuBarTextRefreshState) -> Bool {
        refreshJobs[state.lineKey]?.state === state
    }

    private func scriptAction(for scriptID: UUID) -> ShortcutAction? {
        store.shortcuts.first(where: { $0.id == scriptID }).flatMap { shortcut in
            switch shortcut.action {
            case .runScript, .runScriptFile:
                shortcut.action
            case .launchApp:
                nil
            }
        }
    }

    private func apply(_ content: MenuBarTextContent, to lineKey: MenuBarTextLineKey) {
        guard let slot = slots.first(where: { $0.id == lineKey.slotID }),
            slot.layout.activeLinePositions.contains(lineKey.position),
            slot[lineKey.position].scriptID != nil
        else {
            return
        }

        contentByLineKey[lineKey] = content
    }

    private func saveConfiguration() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(MenuBarTextConfiguration(slots: slots))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("TapTick: Failed to save menu bar text configuration: \(error)")
        }
    }

    private static func loadConfiguration(from fileURL: URL) -> MenuBarTextConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(MenuBarTextConfiguration.self, from: data)
        } catch {
            print("TapTick: Failed to load menu bar text configuration: \(error)")
            return nil
        }
    }
}

private struct MenuBarTextConfiguration: Codable, Sendable {
    let slots: [MenuBarTextSlot]
}

private struct MenuBarTextLineKey: Hashable, Sendable {
    let slotID: UUID
    let position: MenuBarTextLinePosition
}

private struct MenuBarTextRefreshDefinition: Equatable, Sendable {
    let scriptID: UUID
    let refreshIntervalSeconds: Int
}

private struct MenuBarTextRefreshJob {
    let state: MenuBarTextRefreshState
    let task: Task<Void, Never>
}

@MainActor
private final class MenuBarTextRefreshState {
    let lineKey: MenuBarTextLineKey
    private(set) var definition: MenuBarTextRefreshDefinition?
    private(set) var isStopped = false

    private var delayTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    init(
        lineKey: MenuBarTextLineKey,
        definition: MenuBarTextRefreshDefinition
    ) {
        self.lineKey = lineKey
        self.definition = definition
    }

    func update(definition: MenuBarTextRefreshDefinition?) {
        guard self.definition != definition else { return }
        self.definition = definition
        resume()
    }

    func suspend(
        whileDefinitionIs expectedDefinition: MenuBarTextRefreshDefinition?,
        for delay: Duration? = nil
    ) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled,
                    !isStopped,
                    definition == expectedDefinition
                else {
                    continuation.resume()
                    return
                }

                self.continuation = continuation
                guard let delay else { return }
                delayTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: delay)
                    } catch {
                        return
                    }
                    self?.resume()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resume()
            }
        }
    }

    func stop() {
        isStopped = true
        definition = nil
        resume()
    }

    private func resume() {
        delayTask?.cancel()
        delayTask = nil

        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
