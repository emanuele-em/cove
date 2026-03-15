import Foundation
import RediStack

extension RedisBackend {

    func formatRESPValue(_ value: RESPValue) -> String {
        if value.isNull { return "(nil)" }

        if let str = value.string { return str }
        if let n = value.int { return String(n) }

        if let arr = value.array {
            if arr.isEmpty { return "(empty array)" }
            return arr.enumerated().map { i, v in
                "\(i + 1)) \(formatRESPValue(v))"
            }.joined(separator: "\n")
        }

        if let err = value.error { return "(error) \(err.message)" }

        return value.description
    }

    static func parseRedisCommand(_ input: String) -> (command: String, args: [String]) {
        var tokens: [String] = []
        var current = ""
        var inDoubleQuote = false
        var inSingleQuote = false
        var escaped = false

        for ch in input {
            if escaped {
                switch ch {
                case "n": current.append("\n")
                case "t": current.append("\t")
                case "\\": current.append("\\")
                case "\"": current.append("\"")
                default: current.append("\\"); current.append(ch)
                }
                escaped = false
                continue
            }

            if ch == "\\" && !inSingleQuote {
                escaped = true
                continue
            }

            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if ch.isWhitespace && !inDoubleQuote && !inSingleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }

        guard let command = tokens.first else { return ("", []) }
        return (command.uppercased(), Array(tokens.dropFirst()))
    }
}
