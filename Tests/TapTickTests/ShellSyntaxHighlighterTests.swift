import AppKit
import Testing
@testable import TapTickKit

@Suite("ShellSyntaxHighlighter")
struct ShellSyntaxHighlighterTests {
    @Test("Applies colors as temporary layout attributes without changing text storage")
    @MainActor
    func displayOnlyAttributes() {
        let textView = NSTextView()
        textView.string = "if true; then echo done; fi"
        let storedColorBefore =
            textView.textStorage?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor

        ShellSyntaxHighlighter.apply(to: textView, dialect: .zsh)

        let temporaryColor = textView.layoutManager?.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: 0,
            effectiveRange: nil
        )
        let storedColor =
            textView.textStorage?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        #expect(temporaryColor != nil)
        #expect(storedColor?.isEqual(storedColorBefore) == true)
        #expect(textView.string == "if true; then echo done; fi")
    }

    @Test("Recognizes common shell syntax without treating hashes inside words as comments")
    func commonShellTokens() {
        let source = """
            if [[ "$USER" == "root" ]]; then
              echo ${HOME} $?suffix foo#bar # explanation
              exit 42
            fi
            """
        let tokens = ShellSyntaxHighlighter.tokens(in: source, dialect: .zsh)

        #expect(fragments(of: .keyword, in: source, tokens: tokens) == ["if", "then", "fi"])
        #expect(fragments(of: .string, in: source, tokens: tokens) == ["\"$USER\"", "\"root\""])
        #expect(fragments(of: .variable, in: source, tokens: tokens) == ["${HOME}", "$?"])
        #expect(fragments(of: .comment, in: source, tokens: tokens) == ["# explanation"])
        #expect(fragments(of: .number, in: source, tokens: tokens) == ["42"])
    }

    @Test("Uses keywords from the selected shell")
    func shellSpecificKeywords() {
        let source = "function greet; set name $argv; end; foo-if if-foo"

        let fishTokens = ShellSyntaxHighlighter.tokens(in: source, dialect: .fish)
        #expect(
            fragments(of: .keyword, in: source, tokens: fishTokens) == ["function", "set", "end"]
        )

        let bashTokens = ShellSyntaxHighlighter.tokens(in: source, dialect: .bash)
        #expect(fragments(of: .keyword, in: source, tokens: bashTokens) == ["function"])
    }

    @Test("Keeps quoted and nested substitutions together")
    func quotedAndNestedTokens() {
        let source = "echo 'literal # text' $(printf \"%s\" ${value:-42})"
        let tokens = ShellSyntaxHighlighter.tokens(in: source, dialect: .bash)

        #expect(fragments(of: .string, in: source, tokens: tokens) == ["'literal # text'"])
        #expect(
            fragments(of: .variable, in: source, tokens: tokens) == ["$(printf \"%s\" ${value:-42})"]
        )
        #expect(fragments(of: .comment, in: source, tokens: tokens).isEmpty)
    }

    private func fragments(
        of kind: ShellSyntaxTokenKind,
        in source: String,
        tokens: [ShellSyntaxToken]
    ) -> [String] {
        let source = source as NSString
        return
            tokens
            .filter { $0.kind == kind }
            .map { source.substring(with: $0.range) }
    }
}
