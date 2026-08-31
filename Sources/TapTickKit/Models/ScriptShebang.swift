import Foundation

enum ShellDialect: Equatable, Sendable {
    case sh
    case bash
    case zsh
    case fish
}

enum ScriptLanguage: Equatable, Sendable {
    case shell(ShellDialect)
    case python
    case javascript
    case ruby
}

struct ScriptShebang: Equatable, Sendable {
    let line: String
    let interpreterName: String
    let language: ScriptLanguage?

    enum Validation: Equatable, Sendable {
        case valid(ScriptShebang)
        case missing
        case malformed(String)
        case unavailable(String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .valid:
                return "Shebang is valid"
            case .missing:
                return "Add a shebang before running this script"
            case .malformed(let reason):
                return reason
            case .unavailable(let executable):
                return "Interpreter not found: \(executable)"
            }
        }

        var shebang: ScriptShebang? {
            if case .valid(let shebang) = self { return shebang }
            return nil
        }
    }

    static func inspect(_ source: String) -> Validation {
        guard source.hasPrefix("#!") else { return .missing }

        let firstLine = source.prefix { $0 != "\n" && $0 != "\r" }
        let command = firstLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            return .malformed("The shebang does not name an interpreter")
        }

        let components = command.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard let interpreter = components.first, interpreter.hasPrefix("/") else {
            return .malformed("The shebang interpreter must use an absolute path")
        }

        let interpreterURL = URL(fileURLWithPath: interpreter)
        guard FileManager.default.isExecutableFile(atPath: interpreterURL.path) else {
            return .unavailable(interpreter)
        }

        let executableName: String
        if interpreter == "/usr/bin/env" {
            let arguments = Array(components.dropFirst())
            let requestedExecutable: String?
            if arguments.first == "-S" {
                requestedExecutable = arguments.dropFirst().first
            } else {
                requestedExecutable = arguments.first
            }
            guard let requestedExecutable, !requestedExecutable.hasPrefix("-") else {
                return .malformed("The /usr/bin/env shebang must name an executable")
            }
            guard ScriptExecutionEnvironment.resolveExecutable(named: requestedExecutable) != nil else {
                return .unavailable(requestedExecutable)
            }
            executableName = requestedExecutable
        } else {
            executableName = interpreterURL.lastPathComponent
        }

        return .valid(
            ScriptShebang(
                line: String(firstLine),
                interpreterName: executableName,
                language: language(for: executableName)
            )
        )
    }

    static func replacingShebang(in source: String, with shebang: String) -> String {
        if source.hasPrefix("#!") {
            guard let lineEnd = source.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
                return shebang + "\n\n"
            }
            return shebang + source[lineEnd...]
        }

        return source.isEmpty ? shebang + "\n\n" : shebang + "\n\n" + source
    }

    static func language(for executableName: String) -> ScriptLanguage? {
        switch executableName {
        case "sh": .shell(.sh)
        case "bash": .shell(.bash)
        case "zsh": .shell(.zsh)
        case "fish": .shell(.fish)
        case "python", "python3": .python
        case "node", "nodejs": .javascript
        case "ruby": .ruby
        default: nil
        }
    }
}

struct ScriptShebangPreset: Identifiable, Equatable, Sendable {
    let label: String
    let line: String

    var id: String { line }

    static var available: [ScriptShebangPreset] {
        let fixed = [
            ScriptShebangPreset(label: "Zsh", line: "#!/bin/zsh"),
            ScriptShebangPreset(label: "Bash", line: "#!/bin/bash"),
            ScriptShebangPreset(label: "POSIX shell", line: "#!/bin/sh"),
        ]
        let optional = [
            ("Fish", "fish"),
            ("Python 3", "python3"),
            ("Node.js", "node"),
            ("Ruby", "ruby"),
        ].compactMap { label, executable -> ScriptShebangPreset? in
            guard ScriptExecutionEnvironment.resolveExecutable(named: executable) != nil else {
                return nil
            }
            return ScriptShebangPreset(
                label: label,
                line: "#!/usr/bin/env \(executable)"
            )
        }
        return fixed + optional
    }
}

enum ScriptExecutionEnvironment {
    static let pathEntries: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }()

    static let path = pathEntries.joined(separator: ":")

    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        return environment
    }

    static func resolveExecutable(named name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return pathEntries.lazy
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
