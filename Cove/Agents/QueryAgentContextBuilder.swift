import Foundation

enum QueryAgentContextBuilder {
    static func build(
        savedConnection: SavedConnection,
        backend: any DatabaseBackend,
        database: String,
        selectedPath: [String]?,
        treeChildren: [[String]: [HierarchyNode]],
        completionSchema: CompletionSchema?,
        serverVersion: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Connection name: \(savedConnection.name)")
        lines.append("Environment: \(savedConnection.environment.displayName)")
        lines.append("Backend: \(savedConnection.backend.displayName)")
        lines.append("Backend implementation: \(backend.name)")
        lines.append("Server version: \(serverVersion?.nilIfEmpty ?? "unknown")")
        lines.append("Host: \(savedConnection.host)")
        lines.append("Port: \(savedConnection.port)")
        lines.append("Configured database: \(savedConnection.database.nilIfEmpty ?? "none")")
        lines.append("Active query database: \(database.nilIfEmpty ?? "none")")
        lines.append("Selected path: \(selectedPath?.joined(separator: " / ") ?? "none")")
        lines.append("Query language keywords: \(backend.syntaxKeywords.sorted().joined(separator: ", "))")

        if let completionSchema {
            appendCompletionSchema(completionSchema, to: &lines)
        }

        appendLoadedTree(treeChildren, to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendCompletionSchema(_ schema: CompletionSchema, to lines: inout [String]) {
        lines.append("")
        lines.append("Schemas:")
        if schema.schemas.isEmpty {
            lines.append("- none")
        } else {
            for schemaName in schema.schemas.sorted() {
                lines.append("- \(schemaName)")
            }
        }

        lines.append("")
        lines.append("Tables/collections/indexes and fields:")
        if schema.tables.isEmpty {
            lines.append("- none")
        } else {
            for schemaName in schema.tables.keys.sorted() {
                let tables = schema.tables[schemaName] ?? []
                lines.append("- \(schemaName):")
                for table in tables.sorted(by: { $0.name < $1.name }) {
                    let columns = table.columns
                        .map { "\($0.name) \($0.typeName)" }
                        .joined(separator: ", ")
                    lines.append("  - \(table.name): \(columns.isEmpty ? "no known fields" : columns)")
                }
            }
        }

        if !schema.functions.isEmpty {
            lines.append("")
            lines.append("Functions:")
            lines.append(schema.functions.sorted().joined(separator: ", "))
        }

        if !schema.types.isEmpty {
            lines.append("")
            lines.append("Types:")
            lines.append(schema.types.sorted().joined(separator: ", "))
        }
    }

    private static func appendLoadedTree(_ treeChildren: [[String]: [HierarchyNode]], to lines: inout [String]) {
        guard let rootNodes = treeChildren[[]], !rootNodes.isEmpty else { return }
        lines.append("")
        lines.append("Loaded browser tree from root:")
        appendTreeNodes(
            rootNodes,
            parentPath: [],
            treeChildren: treeChildren,
            depth: 0,
            to: &lines
        )
    }

    private static func appendTreeNodes(
        _ nodes: [HierarchyNode],
        parentPath: [String],
        treeChildren: [[String]: [HierarchyNode]],
        depth: Int,
        to lines: inout [String]
    ) {
        for node in nodes {
            let path = parentPath + [node.name]
            let indent = String(repeating: "  ", count: depth)
            let loadedChildren = treeChildren[path]
            let metadata = treeMetadata(for: node, loadedChildren: loadedChildren)
            lines.append("\(indent)- \(node.name)\(metadata)")

            if let loadedChildren, !loadedChildren.isEmpty {
                appendTreeNodes(
                    loadedChildren,
                    parentPath: path,
                    treeChildren: treeChildren,
                    depth: depth + 1,
                    to: &lines
                )
            }
        }
    }

    private static func treeMetadata(for node: HierarchyNode, loadedChildren: [HierarchyNode]?) -> String {
        guard node.isExpandable else { return "" }
        if loadedChildren == nil {
            return " [expandable, not loaded]"
        }
        if loadedChildren?.isEmpty == true {
            return " [expandable, loaded empty]"
        }
        return ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
