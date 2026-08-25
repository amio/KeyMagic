import AppKit

enum ShellSyntaxTokenKind: Equatable {
    case comment
    case keyword
    case number
    case `operator`
    case string
    case variable
}

struct ShellSyntaxToken: Equatable {
    let kind: ShellSyntaxTokenKind
    let range: NSRange
}

/// Produces display-only shell highlighting without changing the editor's plain-text storage.
struct ShellSyntaxHighlighter {
    @MainActor
    static func apply(to textView: NSTextView, shell: ShortcutAction.ShellType) {
        guard let layoutManager = textView.layoutManager else { return }

        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        for token in tokens(in: textView.string, shell: shell) {
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: color(for: token.kind),
                forCharacterRange: token.range
            )
        }
    }

    static func tokens(in text: String, shell: ShortcutAction.ShellType) -> [ShellSyntaxToken] {
        let source = text as NSString
        let reservedWords = keywords(for: shell)
        var tokens: [ShellSyntaxToken] = []
        var index = 0

        while index < source.length {
            let character = source.character(at: index)

            if character == backslash {
                index = min(index + 2, source.length)
                continue
            }

            if character == hash, isCommentStart(in: source, at: index) {
                let end = lineEnd(in: source, from: index)
                tokens.append(token(.comment, from: index, to: end))
                index = end
                continue
            }

            if character == singleQuote || character == doubleQuote {
                let end = quotedEnd(in: source, from: index, quote: character)
                tokens.append(token(.string, from: index, to: end))
                index = end
                continue
            }

            if character == backtick {
                let end = quotedEnd(in: source, from: index, quote: backtick)
                tokens.append(token(.variable, from: index, to: end))
                index = end
                continue
            }

            if character == dollar {
                let end = variableEnd(in: source, from: index)
                tokens.append(token(.variable, from: index, to: end))
                index = end
                continue
            }

            if isDigit(character), isWordBoundary(in: source, before: index) {
                let end = consumeWhile(in: source, from: index + 1, matching: isDigit)
                if isWordBoundary(in: source, after: end) {
                    tokens.append(token(.number, from: index, to: end))
                    index = end
                    continue
                }
                index = end
                continue
            }

            if isIdentifierStart(character) {
                let end = consumeWhile(in: source, from: index + 1, matching: isIdentifierPart)
                let word = source.substring(with: NSRange(location: index, length: end - index))
                if isKeywordBoundary(in: source, before: index),
                    isKeywordBoundary(in: source, after: end),
                    reservedWords.contains(word)
                {
                    tokens.append(token(.keyword, from: index, to: end))
                }
                index = end
                continue
            }

            if isOperator(character) {
                let end = consumeWhile(in: source, from: index + 1, matching: isOperator)
                tokens.append(token(.operator, from: index, to: end))
                index = end
                continue
            }

            index += 1
        }

        return tokens
    }

    private static func color(for kind: ShellSyntaxTokenKind) -> NSColor {
        switch kind {
        case .comment:
            return .secondaryLabelColor
        case .keyword:
            return .systemPink
        case .number:
            return .systemOrange
        case .operator:
            return .systemTeal
        case .string:
            return .systemRed
        case .variable:
            return .systemBlue
        }
    }

    private static func keywords(for shell: ShortcutAction.ShellType) -> Set<String> {
        switch shell {
        case .sh:
            return posixKeywords
        case .bash:
            return posixKeywords.union(["coproc", "function", "select", "time"])
        case .zsh:
            return posixKeywords.union(["coproc", "foreach", "function", "nocorrect", "repeat", "select", "time"])
        case .fish:
            return [
                "and", "begin", "break", "case", "command", "continue", "else", "end", "exec",
                "for", "function", "if", "in", "not", "or", "return", "set", "switch", "while",
            ]
        }
    }

    private static let posixKeywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "fi", "for", "if", "in", "then", "until",
        "while",
    ]

    private static func token(
        _ kind: ShellSyntaxTokenKind,
        from start: Int,
        to end: Int
    ) -> ShellSyntaxToken {
        ShellSyntaxToken(kind: kind, range: NSRange(location: start, length: end - start))
    }

    private static func lineEnd(in source: NSString, from start: Int) -> Int {
        var index = start
        while index < source.length, source.character(at: index) != newline {
            index += 1
        }
        return index
    }

    private static func quotedEnd(in source: NSString, from start: Int, quote: unichar) -> Int {
        var index = start + 1
        while index < source.length {
            let character = source.character(at: index)
            if quote != singleQuote, character == backslash {
                index = min(index + 2, source.length)
                continue
            }
            index += 1
            if character == quote {
                return index
            }
        }
        return source.length
    }

    private static func variableEnd(in source: NSString, from start: Int) -> Int {
        let next = start + 1
        guard next < source.length else { return next }

        switch source.character(at: next) {
        case openBrace:
            return balancedEnd(in: source, from: next, open: openBrace, close: closeBrace)
        case openParenthesis:
            return balancedEnd(in: source, from: next, open: openParenthesis, close: closeParenthesis)
        case singleQuote, doubleQuote:
            return quotedEnd(in: source, from: next, quote: source.character(at: next))
        default:
            let character = source.character(at: next)
            if isIdentifierStart(character) {
                return consumeWhile(in: source, from: next + 1, matching: isIdentifierPart)
            }
            if isDigit(character) || specialVariableCharacters.contains(character) {
                return next + 1
            }
            return next
        }
    }

    private static func balancedEnd(
        in source: NSString,
        from start: Int,
        open: unichar,
        close: unichar
    ) -> Int {
        var depth = 0
        var index = start

        while index < source.length {
            let character = source.character(at: index)
            if character == backslash {
                index = min(index + 2, source.length)
                continue
            }
            if character == singleQuote || character == doubleQuote || character == backtick {
                index = quotedEnd(in: source, from: index, quote: character)
                continue
            }
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }

        return source.length
    }

    private static func consumeWhile(
        in source: NSString,
        from start: Int,
        matching predicate: (unichar) -> Bool
    ) -> Int {
        var index = start
        while index < source.length, predicate(source.character(at: index)) {
            index += 1
        }
        return index
    }

    private static func isCommentStart(in source: NSString, at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = source.character(at: index - 1)
        return isWhitespace(previous) || isOperator(previous)
    }

    private static func isWordBoundary(in source: NSString, before index: Int) -> Bool {
        index == 0 || !isIdentifierPart(source.character(at: index - 1))
    }

    private static func isWordBoundary(in source: NSString, after index: Int) -> Bool {
        index == source.length || !isIdentifierPart(source.character(at: index))
    }

    private static func isKeywordBoundary(in source: NSString, before index: Int) -> Bool {
        index == 0 || isShellDelimiter(source.character(at: index - 1))
    }

    private static func isKeywordBoundary(in source: NSString, after index: Int) -> Bool {
        index == source.length || isShellDelimiter(source.character(at: index))
    }

    private static func isShellDelimiter(_ character: unichar) -> Bool {
        isWhitespace(character) || isOperator(character)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == space || character == tab || character == newline || character == carriageReturn
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= asciiZero && character <= asciiNine
    }

    private static func isIdentifierStart(_ character: unichar) -> Bool {
        character == underscore
            || (character >= asciiUpperA && character <= asciiUpperZ)
            || (character >= asciiLowerA && character <= asciiLowerZ)
    }

    private static func isIdentifierPart(_ character: unichar) -> Bool {
        isIdentifierStart(character) || isDigit(character)
    }

    private static func isOperator(_ character: unichar) -> Bool {
        operatorCharacters.contains(character)
    }

    private static let specialVariableCharacters = Set("@*#?$!-".utf16)
    private static let operatorCharacters = Set("|&;<>(){}[]".utf16)

    private static let tab: unichar = 0x09
    private static let newline: unichar = 0x0A
    private static let carriageReturn: unichar = 0x0D
    private static let space: unichar = 0x20
    private static let hash: unichar = 0x23
    private static let dollar: unichar = 0x24
    private static let singleQuote: unichar = 0x27
    private static let openParenthesis: unichar = 0x28
    private static let closeParenthesis: unichar = 0x29
    private static let asciiZero: unichar = 0x30
    private static let asciiNine: unichar = 0x39
    private static let openBrace: unichar = 0x7B
    private static let closeBrace: unichar = 0x7D
    private static let doubleQuote: unichar = 0x22
    private static let asciiUpperA: unichar = 0x41
    private static let asciiUpperZ: unichar = 0x5A
    private static let backslash: unichar = 0x5C
    private static let underscore: unichar = 0x5F
    private static let backtick: unichar = 0x60
    private static let asciiLowerA: unichar = 0x61
    private static let asciiLowerZ: unichar = 0x7A
}
