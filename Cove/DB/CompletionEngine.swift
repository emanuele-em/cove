import Foundation

private enum CompletionContext {
    case general
    case tableRef
    case expression
}

enum CompletionEngine {

    static func complete(
        text: String,
        cursor: Int,
        schema: CompletionSchema,
        keywords: Set<String>
    ) -> [CompletionItem] {
        let chars = Array(text.utf16)
        let cursorPos = min(cursor, chars.count)

        if isInStringOrComment(chars: chars, cursor: cursorPos) {
            return []
        }

        var wordStart = cursorPos
        while wordStart > 0 && isIdent(chars[wordStart - 1]) {
            wordStart -= 1
        }

        let prefix = wordStart < cursorPos
            ? (text as NSString).substring(with: NSRange(location: wordStart, length: cursorPos - wordStart)).lowercased()
            : ""

        if wordStart > 0 && chars[wordStart - 1] == 0x2E {
            var beforeDot = wordStart - 1
            while beforeDot > 0 && isIdent(chars[beforeDot - 1]) { beforeDot -= 1 }
            let qualifier = (text as NSString)
                .substring(with: NSRange(location: beforeDot, length: wordStart - 1 - beforeDot))
                .lowercased()
            let aliases = extractAliases(text: text)
            return dotComplete(qualifier: qualifier, prefix: prefix, schema: schema, aliases: aliases)
        }

        guard !prefix.isEmpty else { return [] }

        let context = analyzeContext(text: text, position: wordStart)
        var items: [CompletionItem] = []

        switch context {
        case .tableRef:
            items += matchTables(schema: schema, prefix: prefix)
            items += matchSchemas(schema: schema, prefix: prefix)
        case .expression:
            items += matchColumns(schema: schema, prefix: prefix)
            items += matchFunctions(schema: schema, prefix: prefix)
            items += matchKeywords(keywords: keywords, prefix: prefix)
            items += matchTables(schema: schema, prefix: prefix)
        case .general:
            items += matchKeywords(keywords: keywords, prefix: prefix)
            items += matchTables(schema: schema, prefix: prefix)
            items += matchFunctions(schema: schema, prefix: prefix)
            items += matchColumns(schema: schema, prefix: prefix)
        }

        if items.count == 1 && items[0].insertText.lowercased() == prefix {
            return []
        }

        return Array(items.prefix(50))
    }

    static func isIdent(_ c: UTF16.CodeUnit) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39) || c == 0x5F
    }

    // MARK: - Alias extraction

    private static func extractAliases(text: String) -> [String: String] {
        let tokens = tokenizeForAliases(text)
        var aliases: [String: String] = [:]

        let fromKeywords: Set<String> = ["FROM", "JOIN"]
        let stopKeywords: Set<String> = [
            "WHERE", "ON", "ORDER", "GROUP", "HAVING", "LIMIT", "OFFSET",
            "UNION", "SELECT", "INSERT", "UPDATE", "DELETE", "SET",
            "VALUES", "RETURNING", "LEFT", "RIGHT", "INNER", "OUTER",
            "CROSS", "NATURAL", "FULL", "JOIN", "LATERAL", "USING",
        ]

        var i = 0
        while i < tokens.count {
            if fromKeywords.contains(tokens[i].uppercased()) {
                i += 1
                while i < tokens.count {
                    let upper = tokens[i].uppercased()
                    if stopKeywords.contains(upper) || fromKeywords.contains(upper) { break }
                    if tokens[i] == "," { i += 1; continue }

                    let tableName = tokens[i]
                    i += 1

                    if i < tokens.count {
                        let next = tokens[i].uppercased()
                        if next == "AS" {
                            i += 1
                            if i < tokens.count && !stopKeywords.contains(tokens[i].uppercased()) {
                                aliases[tokens[i].lowercased()] = bareTableName(tableName)
                                i += 1
                            }
                        } else if next != "," && !stopKeywords.contains(next) && !fromKeywords.contains(next) {
                            aliases[tokens[i].lowercased()] = bareTableName(tableName)
                            i += 1
                        }
                    }
                }
            } else {
                i += 1
            }
        }

        return aliases
    }

    /// Tokenize keeping dot-separated identifiers together (e.g. "public.users") and commas.
    private static func tokenizeForAliases(_ text: String) -> [String] {
        var tokens: [String] = []
        let chars = Array(text.utf16)
        let len = chars.count
        var i = 0

        while i < len {
            if isIdent(chars[i]) {
                let start = i
                while i < len {
                    if isIdent(chars[i]) {
                        i += 1
                    } else if chars[i] == 0x2E && i + 1 < len && isIdent(chars[i + 1]) {
                        i += 1 // consume dot, loop continues with next ident char
                    } else {
                        break
                    }
                }
                tokens.append((text as NSString).substring(with: NSRange(location: start, length: i - start)))
            } else if chars[i] == 0x2C {
                tokens.append(",")
                i += 1
            } else {
                i += 1
            }
        }
        return tokens
    }

    /// "public.locations" → "locations"
    private static func bareTableName(_ qualified: String) -> String {
        if let dot = qualified.lastIndex(of: ".") {
            return String(qualified[qualified.index(after: dot)...]).lowercased()
        }
        return qualified.lowercased()
    }

    // MARK: - Dot completion

    private static func dotComplete(
        qualifier: String,
        prefix: String,
        schema: CompletionSchema,
        aliases: [String: String]
    ) -> [CompletionItem] {
        if let schemaKey = schema.schemas.first(where: { $0.lowercased() == qualifier }),
           let tables = schema.tables[schemaKey] {
            return tables
                .filter { prefix.isEmpty || $0.name.lowercased().hasPrefix(prefix) }
                .map { CompletionItem(label: $0.name, detail: "table", kind: .table, insertText: $0.name) }
        }

        let resolvedName = aliases[qualifier] ?? qualifier

        for (_, tables) in schema.tables {
            if let table = tables.first(where: { $0.name.lowercased() == resolvedName }) {
                return table.columns
                    .filter { prefix.isEmpty || $0.name.lowercased().hasPrefix(prefix) }
                    .map { CompletionItem(label: $0.name, detail: $0.typeName, kind: .column, insertText: $0.name) }
            }
        }

        return []
    }

    // MARK: - Context analysis

    private static func analyzeContext(text: String, position: Int) -> CompletionContext {
        let words = extractWords(text, upTo: position)

        for i in stride(from: words.count - 1, through: 0, by: -1) {
            let word = words[i].uppercased()
            switch word {
            case "FROM", "JOIN", "INTO", "UPDATE":
                return .tableRef
            case "TABLE", "VIEW", "KEYSPACE", "DATABASE", "SCHEMA":
                if i > 0 && ["DROP", "ALTER", "CREATE", "TRUNCATE"].contains(words[i - 1].uppercased()) {
                    return .tableRef
                }
                continue
            case "SELECT", "WHERE", "HAVING", "SET", "AND", "OR", "ON":
                return .expression
            case "BY":
                if i > 0 && ["ORDER", "GROUP"].contains(words[i - 1].uppercased()) {
                    return .expression
                }
                continue
            default:
                continue
            }
        }

        return .general
    }

    // MARK: - Matching

    private static func matchKeywords(keywords: Set<String>, prefix: String) -> [CompletionItem] {
        keywords
            .filter { $0.lowercased().hasPrefix(prefix) && $0.lowercased() != prefix }
            .sorted()
            .map { CompletionItem(label: $0, detail: "keyword", kind: .keyword, insertText: $0) }
    }

    private static func matchTables(schema: CompletionSchema, prefix: String) -> [CompletionItem] {
        var items: [CompletionItem] = []
        for (_, tables) in schema.tables {
            for table in tables where table.name.lowercased().hasPrefix(prefix) {
                items.append(CompletionItem(label: table.name, detail: "table", kind: .table, insertText: table.name))
            }
        }
        return items.sorted { $0.label < $1.label }
    }

    private static func matchColumns(schema: CompletionSchema, prefix: String) -> [CompletionItem] {
        var items: [CompletionItem] = []
        var seen = Set<String>()
        for (_, tables) in schema.tables {
            for table in tables {
                for col in table.columns where col.name.lowercased().hasPrefix(prefix) {
                    if seen.insert(col.name.lowercased()).inserted {
                        items.append(CompletionItem(label: col.name, detail: col.typeName, kind: .column, insertText: col.name))
                    }
                }
            }
        }
        return items.sorted { $0.label < $1.label }
    }

    private static func matchFunctions(schema: CompletionSchema, prefix: String) -> [CompletionItem] {
        schema.functions
            .filter { $0.lowercased().hasPrefix(prefix) }
            .sorted()
            .map { CompletionItem(label: $0, detail: "function", kind: .function, insertText: $0) }
    }

    private static func matchSchemas(schema: CompletionSchema, prefix: String) -> [CompletionItem] {
        schema.schemas
            .filter { $0.lowercased().hasPrefix(prefix) }
            .sorted()
            .map { CompletionItem(label: $0, detail: "schema", kind: .schema, insertText: $0) }
    }

    // MARK: - Helpers

    private static func extractWords(_ text: String, upTo position: Int) -> [String] {
        var words: [String] = []
        let chars = Array(text.utf16)
        var i = 0
        let len = min(position, chars.count)

        while i < len {
            if isIdent(chars[i]) {
                let start = i
                while i < len && isIdent(chars[i]) { i += 1 }
                words.append((text as NSString).substring(with: NSRange(location: start, length: i - start)))
            } else {
                i += 1
            }
        }
        return words
    }

    private static func isInStringOrComment(chars: [UTF16.CodeUnit], cursor: Int) -> Bool {
        var i = 0
        let len = chars.count

        while i < len && i < cursor {
            if i + 1 < len && chars[i] == 0x2D && chars[i + 1] == 0x2D {
                var end = i + 2
                while end < len && chars[end] != 0x0A { end += 1 }
                if cursor <= end { return true }
                i = end
                continue
            }

            if i + 1 < len && chars[i] == 0x2F && chars[i + 1] == 0x2A {
                let start = i
                i += 2
                while i + 1 < len && !(chars[i] == 0x2A && chars[i + 1] == 0x2F) { i += 1 }
                let end = i + 1 < len ? i + 2 : len
                if cursor > start && cursor < end { return true }
                i = end
                continue
            }

            if chars[i] == 0x27 {
                let start = i
                i += 1
                while i < len && chars[i] != 0x27 { i += 1 }
                let end = i < len ? i + 1 : len + 1
                if cursor > start && cursor < end { return true }
                i = end
                continue
            }

            i += 1
        }

        return false
    }
}
