import Foundation

enum QueryAgentPromptBuilder {
    static func prompt(for request: QueryAgentRequest) -> String {
        """
        You are helping write a database query in Cove.

        Rules:
        - Return ONLY the query or database command text.
        - Do not use Markdown.
        - Do not wrap the query in code fences.
        - Do not explain the query.
        - Do not include prose before or after the query.
        - Use the exact query language for the backend in the database context.
        - Use only table, collection, index, schema, and field names present in the database context.
        - Do not invent or guess database object names.
        - If the current query block is present, treat the user request as an edit or correction of that block unless the user explicitly asks for a new query.

        Database context:
        \(request.databaseContext)

        Current query block:
        \(request.currentQuery.isEmpty ? "(empty)" : request.currentQuery)

        User request:
        \(request.instruction)
        """
    }

    static func sanitizeAgentResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let fenced = fencedCodeBody(in: trimmed) {
            return fenced.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func fencedCodeBody(in text: String) -> String? {
        guard let firstFence = text.range(of: "```") else { return nil }
        let afterFence = text[firstFence.upperBound...]
        guard let closingFence = afterFence.range(of: "```") else { return nil }

        var body = String(afterFence[..<closingFence.lowerBound])
        if let newline = body.firstIndex(of: "\n") {
            let firstLine = body[..<newline].trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstLine.isEmpty && !firstLine.contains(" ") {
                body = String(body[body.index(after: newline)...])
            }
        }
        return body
    }
}
