import AppKit
import Foundation

enum SQLTokenKind {
    case normal
    case keyword
    case string
    case number
    case comment
}

struct SQLToken {
    let range: NSRange
    let kind: SQLTokenKind
}

enum SQLHighlighter {
    static func tokenize(_ text: String, keywords: Set<String>) -> [SQLToken] {
        var tokens: [SQLToken] = []
        let chars = Array(text.utf16)
        let len = chars.count
        var i = 0

        while i < len {
            // Line comment
            if i + 1 < len && chars[i] == 0x2D && chars[i + 1] == 0x2D { // --
                let start = i
                while i < len && chars[i] != 0x0A { i += 1 }
                tokens.append(SQLToken(range: NSRange(location: start, length: i - start), kind: .comment))
                continue
            }

            // Block comment
            if i + 1 < len && chars[i] == 0x2F && chars[i + 1] == 0x2A { // /*
                let start = i
                i += 2
                while i + 1 < len && !(chars[i] == 0x2A && chars[i + 1] == 0x2F) { i += 1 }
                if i + 1 < len { i += 2 } else { i = len }
                tokens.append(SQLToken(range: NSRange(location: start, length: i - start), kind: .comment))
                continue
            }

            // String literal
            if chars[i] == 0x27 { // '
                let start = i
                i += 1
                while i < len && chars[i] != 0x27 { i += 1 }
                if i < len { i += 1 }
                tokens.append(SQLToken(range: NSRange(location: start, length: i - start), kind: .string))
                continue
            }

            // Number
            if isDigit(chars[i]) || (chars[i] == 0x2E && i + 1 < len && isDigit(chars[i + 1])) {
                let start = i
                while i < len && (isDigit(chars[i]) || chars[i] == 0x2E) { i += 1 }
                tokens.append(SQLToken(range: NSRange(location: start, length: i - start), kind: .number))
                continue
            }

            // Word
            if isAlpha(chars[i]) || chars[i] == 0x5F { // _
                let start = i
                while i < len && (isAlphaNum(chars[i]) || chars[i] == 0x5F) { i += 1 }
                let range = NSRange(location: start, length: i - start)
                let word = (text as NSString).substring(with: range).uppercased()
                let kind: SQLTokenKind = keywords.contains(word) ? .keyword : .normal
                tokens.append(SQLToken(range: range, kind: kind))
                continue
            }

            i += 1
        }

        return tokens
    }

    static func colorFor(_ kind: SQLTokenKind) -> NSColor {
        switch kind {
        case .normal: .labelColor
        case .keyword: .systemBlue
        case .string: .systemOrange
        case .number: .systemGreen
        case .comment: .systemGray
        }
    }

    private static func isDigit(_ c: UTF16.CodeUnit) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isAlpha(_ c: UTF16.CodeUnit) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }
    private static func isAlphaNum(_ c: UTF16.CodeUnit) -> Bool { isAlpha(c) || isDigit(c) }
}
