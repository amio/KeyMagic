import Foundation

/** The number of independently configured rows rendered by a menu bar slot. */
enum MenuBarTextLayout: String, Codable, CaseIterable, Sendable {
    case singleLine
    case twoLines

    var title: String {
        switch self {
        case .singleLine:
            "Single Line"
        case .twoLines:
            "Two Lines"
        }
    }

    var activeLinePositions: [MenuBarTextLinePosition] {
        switch self {
        case .singleLine:
            [.top]
        case .twoLines:
            [.top, .bottom]
        }
    }
}

/** Horizontal text alignment shared by every active row in a slot. */
enum MenuBarTextAlignment: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right

    var title: String {
        switch self {
        case .left:
            "Left"
        case .center:
            "Center"
        case .right:
            "Right"
        }
    }

    var systemImage: String {
        switch self {
        case .left:
            "text.alignleft"
        case .center:
            "text.aligncenter"
        case .right:
            "text.alignright"
        }
    }
}

/** A stable position within a menu bar text slot. */
enum MenuBarTextLinePosition: Int, Hashable, Sendable {
    case top
    case bottom
}

/** The script source and independent refresh cadence for one rendered text row. */
struct MenuBarTextLineConfiguration: Codable, Equatable, Sendable {
    static let defaultRefreshIntervalSeconds = 3
    static let refreshIntervalRange = 1...3600

    var scriptID: UUID?
    var refreshIntervalSeconds: Int

    init(
        scriptID: UUID? = nil,
        refreshIntervalSeconds: Int = defaultRefreshIntervalSeconds
    ) {
        self.scriptID = scriptID
        self.refreshIntervalSeconds = refreshIntervalSeconds
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scriptID = try container.decodeIfPresent(UUID.self, forKey: .scriptID)
        refreshIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds)
            ?? Self.defaultRefreshIntervalSeconds
        normalize()
    }

    mutating func normalize() {
        refreshIntervalSeconds = refreshIntervalSeconds.clamped(to: Self.refreshIntervalRange)
    }
}

/** A persisted menu bar segment with one or two independently refreshed rows. */
struct MenuBarTextSlot: Identifiable, Codable, Equatable, Sendable {
    static let defaultWidthPoints = 50
    static let widthRange = 24...240

    let id: UUID
    var layout: MenuBarTextLayout
    var alignment: MenuBarTextAlignment
    var widthPoints: Int
    var topLine: MenuBarTextLineConfiguration
    var bottomLine: MenuBarTextLineConfiguration

    init(
        id: UUID = UUID(),
        layout: MenuBarTextLayout = .singleLine,
        alignment: MenuBarTextAlignment = .center,
        widthPoints: Int = defaultWidthPoints,
        topLine: MenuBarTextLineConfiguration = MenuBarTextLineConfiguration(),
        bottomLine: MenuBarTextLineConfiguration = MenuBarTextLineConfiguration()
    ) {
        self.id = id
        self.layout = layout
        self.alignment = alignment
        self.widthPoints = widthPoints
        self.topLine = topLine
        self.bottomLine = bottomLine
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        if let layout = try container.decodeIfPresent(MenuBarTextLayout.self, forKey: .layout) {
            self.layout = layout
            alignment =
                try container.decodeIfPresent(MenuBarTextAlignment.self, forKey: .alignment)
                ?? .center
            widthPoints =
                try container.decodeIfPresent(Int.self, forKey: .widthPoints)
                ?? Self.defaultWidthPoints
            topLine =
                try container.decodeIfPresent(MenuBarTextLineConfiguration.self, forKey: .topLine)
                ?? MenuBarTextLineConfiguration()
            bottomLine =
                try container.decodeIfPresent(MenuBarTextLineConfiguration.self, forKey: .bottomLine)
                ?? MenuBarTextLineConfiguration()
        } else {
            let legacyLineCount = try container.decodeIfPresent(Int.self, forKey: .lineCount) ?? 1
            let legacyScriptID = try container.decodeIfPresent(UUID.self, forKey: .scriptID)
            let legacyRefreshInterval =
                try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds)
                ?? MenuBarTextLineConfiguration.defaultRefreshIntervalSeconds

            layout = legacyLineCount == 2 ? .twoLines : .singleLine
            alignment = .center
            widthPoints = Self.defaultWidthPoints
            topLine = MenuBarTextLineConfiguration(
                scriptID: legacyScriptID,
                refreshIntervalSeconds: legacyRefreshInterval
            )
            bottomLine = MenuBarTextLineConfiguration()
        }
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layout, forKey: .layout)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(widthPoints, forKey: .widthPoints)
        try container.encode(topLine, forKey: .topLine)
        try container.encode(bottomLine, forKey: .bottomLine)
    }

    subscript(position: MenuBarTextLinePosition) -> MenuBarTextLineConfiguration {
        get {
            switch position {
            case .top:
                topLine
            case .bottom:
                bottomLine
            }
        }
        set {
            switch position {
            case .top:
                topLine = newValue
            case .bottom:
                bottomLine = newValue
            }
        }
    }

    var hasActiveScript: Bool {
        layout.activeLinePositions.contains { self[$0].scriptID != nil }
    }

    mutating func normalize() {
        widthPoints = widthPoints.clamped(to: Self.widthRange)
        topLine.normalize()
        bottomLine.normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case layout
        case alignment
        case widthPoints
        case topLine
        case bottomLine
        case scriptID
        case lineCount
        case refreshIntervalSeconds
    }
}

/** Display-ready single-line output shared by the menu bar renderer and Settings preview. */
struct MenuBarTextContent: Equatable, Sendable {
    let text: String
    let isPlaceholder: Bool

    static func scriptResult(_ result: ScriptExecutionResult) -> Self {
        let normalizedOutput = normalizeWhitespace(result.output)
        if !normalizedOutput.isEmpty {
            return Self(text: normalizedOutput, isPlaceholder: false)
        }

        return result.succeeded
            ? Self(text: "—", isPlaceholder: false)
            : Self(text: "Error (\(result.exitCode))", isPlaceholder: false)
    }

    static let empty = Self(text: "", isPlaceholder: false)
    static let loading = Self(text: "…", isPlaceholder: false)
    static let unavailable = Self(text: "Script unavailable", isPlaceholder: false)
    static let chooseScript = Self(text: "Choose a script", isPlaceholder: true)

    private static func normalizeWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }
}

/** Fixed-width display data consumed by the shared menu bar renderer. */
struct MenuBarTextRenderedSlot: Identifiable, Equatable, Sendable {
    let id: UUID
    let alignment: MenuBarTextAlignment
    let widthPoints: Int
    let contents: [MenuBarTextContent]
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
