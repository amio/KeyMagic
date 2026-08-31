import AppKit
import SwiftTreeSitter
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterRuby

enum ScriptSyntaxTokenKind: Equatable, Sendable {
    case comment
    case constant
    case function
    case keyword
    case number
    case `operator`
    case property
    case punctuation
    case string
    case type
    case variable
}

struct ScriptSyntaxToken: Equatable, Sendable {
    let kind: ScriptSyntaxTokenKind
    let range: NSRange
}

/// Owns the shared display palette and applies syntax colors without mutating text storage.
struct ScriptSyntaxHighlighter {
    @MainActor
    static func apply(_ tokens: [ScriptSyntaxToken], to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }

        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        for token in tokens where token.range.length > 0 && NSMaxRange(token.range) <= fullRange.length {
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: color(for: token.kind),
                forCharacterRange: token.range
            )
        }
    }

    @MainActor
    static func clear(_ textView: NSTextView) {
        apply([], to: textView)
    }

    private static func color(for kind: ScriptSyntaxTokenKind) -> NSColor {
        switch kind {
        case .comment:
            return .secondaryLabelColor
        case .constant:
            return .systemOrange
        case .function:
            return .systemBlue
        case .keyword:
            return .systemPink
        case .number:
            return .systemOrange
        case .operator:
            return .systemTeal
        case .property:
            return .systemPurple
        case .punctuation:
            return .secondaryLabelColor
        case .string:
            return .systemRed
        case .type:
            return .systemTeal
        case .variable:
            return .textColor
        }
    }
}

/// Serializes access to one parser and keeps all Tree-sitter work off the main actor.
actor TreeSitterSyntaxHighlighter {
    static let shared = TreeSitterSyntaxHighlighter()

    private let parser = Parser()
    private var configurations: [TreeLanguage: LanguageConfiguration] = [:]

    func tokens(in source: String, language: ScriptLanguage) throws -> [ScriptSyntaxToken] {
        guard let treeLanguage = TreeLanguage(language) else { return [] }
        try Task.checkCancellation()

        let configuration = try configuration(for: treeLanguage)
        try parser.setLanguage(configuration.language)
        guard
            let tree = parser.parse(source),
            let query = configuration.queries[.highlights]
        else {
            return []
        }

        try Task.checkCancellation()
        let sourceLength = (source as NSString).length
        return
            query
            .execute(in: tree)
            .resolve(with: .init(string: source))
            .highlights()
            .compactMap { highlight in
                guard
                    let kind = Self.tokenKind(for: highlight.nameComponents),
                    highlight.range.length > 0,
                    NSMaxRange(highlight.range) <= sourceLength
                else {
                    return nil
                }
                return ScriptSyntaxToken(kind: kind, range: highlight.range)
            }
    }

    private func configuration(for language: TreeLanguage) throws -> LanguageConfiguration {
        if let configuration = configurations[language] {
            return configuration
        }

        let configuration: LanguageConfiguration
        switch language {
        case .python:
            configuration = try Self.configuration(
                tree_sitter_python(),
                name: "Python",
                bundleName: "TreeSitterPython_TreeSitterPython"
            )
        case .javascript:
            configuration = try Self.configuration(
                tree_sitter_javascript(),
                name: "JavaScript",
                bundleName: "TreeSitterJavaScript_TreeSitterJavaScript"
            )
        case .ruby:
            configuration = try Self.configuration(
                tree_sitter_ruby(),
                name: "Ruby",
                bundleName: "TreeSitterRuby_TreeSitterRuby"
            )
        }
        configurations[language] = configuration
        return configuration
    }

    private static func configuration(
        _ language: OpaquePointer,
        name: String,
        bundleName: String
    ) throws -> LanguageConfiguration {
        let hostBundles = [Bundle(for: SyntaxBundleMarker.self), Bundle.main]
        for hostBundle in hostBundles {
            guard
                let bundleURL = hostBundle.url(forResource: bundleName, withExtension: "bundle"),
                let resourceURL = Bundle(url: bundleURL)?.resourceURL
            else {
                continue
            }

            let queriesURL = resourceURL.appendingPathComponent("queries", isDirectory: true)
            if FileManager.default.isReadableFile(atPath: queriesURL.path) {
                return try LanguageConfiguration(language, name: name, queriesURL: queriesURL)
            }
        }

        throw TreeSitterSyntaxHighlighterError.queryBundleNotFound(bundleName)
    }

    private static func tokenKind(for nameComponents: [String]) -> ScriptSyntaxTokenKind? {
        guard let category = nameComponents.first else { return nil }

        switch category {
        case "comment":
            return .comment
        case "boolean", "constant", "none":
            return .constant
        case "function", "method":
            return .function
        case "conditional", "exception", "include", "keyword", "repeat":
            return .keyword
        case "float", "number":
            return .number
        case "operator":
            return .operator
        case "attribute", "field", "label", "property":
            return .property
        case "punctuation":
            return .punctuation
        case "character", "escape", "string":
            return .string
        case "constructor", "module", "namespace", "tag", "type":
            return .type
        case "embedded", "variable":
            return .variable
        default:
            return nil
        }
    }

    private enum TreeLanguage: Hashable {
        case python
        case javascript
        case ruby

        init?(_ language: ScriptLanguage) {
            switch language {
            case .python:
                self = .python
            case .javascript:
                self = .javascript
            case .ruby:
                self = .ruby
            case .shell:
                return nil
            }
        }
    }
}

private final class SyntaxBundleMarker: NSObject {}

private enum TreeSitterSyntaxHighlighterError: Error {
    case queryBundleNotFound(String)
}
