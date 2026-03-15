import Foundation

enum CompletionKind: Sendable {
    case keyword
    case table
    case column
    case function
    case schema
    case type
}

struct CompletionItem: Sendable {
    let label: String
    let detail: String
    let kind: CompletionKind
    let insertText: String
}

struct CompletionColumn: Sendable {
    let name: String
    let typeName: String
}

struct CompletionTable: Sendable {
    let name: String
    let columns: [CompletionColumn]
}

struct CompletionSchema: Sendable {
    var schemas: [String]
    var tables: [String: [CompletionTable]]
    var functions: [String]
    var types: [String]

    static let empty = CompletionSchema(schemas: [], tables: [:], functions: [], types: [])
}
