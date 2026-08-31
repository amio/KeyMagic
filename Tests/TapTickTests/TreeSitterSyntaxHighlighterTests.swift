import Foundation
import Testing
@testable import TapTickKit

@Suite("TreeSitterSyntaxHighlighter")
struct TreeSitterSyntaxHighlighterTests {
    @Test("Highlights representative Python syntax")
    func python() async throws {
        let source = """
            # greeting
            def greet(name):
                return "hello" if name else 42
            """

        let tokens = try await TreeSitterSyntaxHighlighter.shared.tokens(
            in: source,
            language: .python
        )

        #expect(fragments(of: .comment, in: source, tokens: tokens).contains("# greeting"))
        #expect(fragments(of: .keyword, in: source, tokens: tokens).contains("def"))
        #expect(fragments(of: .string, in: source, tokens: tokens).contains("\"hello\""))
        #expect(fragments(of: .number, in: source, tokens: tokens).contains("42"))
    }

    @Test("Highlights representative JavaScript syntax")
    func javascript() async throws {
        let source = """
            const answer = 42; // result
            console.log("hello")
            """

        let tokens = try await TreeSitterSyntaxHighlighter.shared.tokens(
            in: source,
            language: .javascript
        )

        #expect(fragments(of: .keyword, in: source, tokens: tokens).contains("const"))
        #expect(fragments(of: .comment, in: source, tokens: tokens).contains("// result"))
        #expect(fragments(of: .string, in: source, tokens: tokens).contains("\"hello\""))
        #expect(fragments(of: .number, in: source, tokens: tokens).contains("42"))
    }

    @Test("Highlights representative Ruby syntax")
    func ruby() async throws {
        let source = """
            # greeting
            def greet(name)
              puts "hello"
            end
            """

        let tokens = try await TreeSitterSyntaxHighlighter.shared.tokens(
            in: source,
            language: .ruby
        )

        #expect(fragments(of: .comment, in: source, tokens: tokens).contains("# greeting"))
        #expect(fragments(of: .keyword, in: source, tokens: tokens).contains("def"))
        #expect(fragments(of: .keyword, in: source, tokens: tokens).contains("end"))
        #expect(fragments(of: .string, in: source, tokens: tokens).contains("\"hello\""))
    }

    @Test("Returns Foundation UTF-16 ranges after non-BMP characters")
    func utf16Ranges() async throws {
        let source = "value = \"😀\"\nif value:\n    print(value)"
        let tokens = try await TreeSitterSyntaxHighlighter.shared.tokens(
            in: source,
            language: .python
        )

        #expect(fragments(of: .keyword, in: source, tokens: tokens).contains("if"))
    }

    private func fragments(
        of kind: ScriptSyntaxTokenKind,
        in source: String,
        tokens: [ScriptSyntaxToken]
    ) -> [String] {
        let source = source as NSString
        return
            tokens
            .filter { $0.kind == kind }
            .map { source.substring(with: $0.range) }
    }
}
