import XCTest
@testable import Cove

final class QueryAgentPromptBuilderTests: XCTestCase {
    func testSanitizePlainQuery() {
        let query = QueryAgentPromptBuilder.sanitizeAgentResponse("  SELECT * FROM users  \n")
        XCTAssertEqual(query, "SELECT * FROM users")
    }

    func testSanitizeFencedQuery() {
        let query = QueryAgentPromptBuilder.sanitizeAgentResponse("""
        ```sql
        SELECT * FROM users
        ```
        """)
        XCTAssertEqual(query, "SELECT * FROM users")
    }

    func testPromptRequiresQueryOnlyOutput() {
        let prompt = QueryAgentPromptBuilder.prompt(for: QueryAgentRequest(
            instruction: "show active users",
            currentQuery: "",
            databaseContext: "Backend: PostgreSQL"
        ))

        XCTAssertTrue(prompt.contains("Return ONLY the query"))
        XCTAssertTrue(prompt.contains("Backend: PostgreSQL"))
        XCTAssertTrue(prompt.contains("show active users"))
    }

    func testCodexUsesLocalCLI() {
        let args = QueryAgentKind.codex.arguments(
            workspaceURL: URL(fileURLWithPath: "/tmp/cove-agent"),
            outputURL: URL(fileURLWithPath: "/tmp/cove-output.txt")
        )

        XCTAssertEqual(QueryAgentKind.codex.executableNames, ["codex"])
        XCTAssertEqual(args.first, "exec")
        XCTAssertFalse(args.contains("--ask-for-approval"))
        XCTAssertTrue(args.contains("--output-last-message"))
        XCTAssertTrue(args.contains("-"))
    }

    func testClaudeUsesLocalCLI() {
        let args = QueryAgentKind.claude.arguments(
            workspaceURL: URL(fileURLWithPath: "/tmp/cove-agent"),
            outputURL: nil
        )

        XCTAssertEqual(QueryAgentKind.claude.executableNames, ["claude"])
        XCTAssertTrue(args.contains("--print"))
        XCTAssertTrue(args.contains("--no-session-persistence"))
    }

    func testAgentContextUsesLoadedTreeFromRootEvenWhenCollapsed() {
        let schemaTint = NodeTint(r: 0, g: 0, b: 1)
        let tableTint = NodeTint(r: 0, g: 1, b: 0)
        let columnTint = NodeTint(r: 1, g: 1, b: 1)
        let context = QueryAgentContextBuilder.build(
            savedConnection: SavedConnection(
                name: "Local",
                backend: .postgres,
                host: "localhost",
                port: "5432",
                user: "postgres",
                database: "app"
            ),
            backend: StubBackend(),
            database: "app",
            selectedPath: nil,
            treeChildren: [
                []: [
                    HierarchyNode(name: "public", icon: "folder", tint: schemaTint, isExpandable: true)
                ],
                ["public"]: [
                    HierarchyNode(name: "users", icon: "tablecells", tint: tableTint, isExpandable: true),
                    HierarchyNode(name: "orders", icon: "tablecells", tint: tableTint, isExpandable: true)
                ],
                ["public", "users"]: [
                    HierarchyNode(name: "id", icon: "number", tint: columnTint, isExpandable: false),
                    HierarchyNode(name: "email", icon: "textformat", tint: columnTint, isExpandable: false)
                ]
            ],
            completionSchema: nil,
            serverVersion: "test"
        )

        XCTAssertTrue(context.contains("Loaded browser tree from root:"))
        XCTAssertTrue(context.contains("- public"))
        XCTAssertTrue(context.contains("  - users"))
        XCTAssertTrue(context.contains("    - email"))
        XCTAssertTrue(context.contains("  - orders [expandable, not loaded]"))
    }
}

private struct StubBackend: DatabaseBackend {
    let name = "Stub"
    let syntaxKeywords: Set<String> = ["SELECT", "FROM"]

    func listChildren(path: [String]) async throws -> [HierarchyNode] { [] }
    func isDataBrowsable(path: [String]) -> Bool { false }
    func isEditable(path: [String]) -> Bool { false }
    func isStructureEditable(path: [String]) -> Bool { false }
    func fetchTableData(path: [String], limit: UInt32, offset: UInt32, sort: (column: String, direction: SortDirection)?) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
    }
    func fetchNodeDetails(path: [String]) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
    }
    func executeQuery(database: String, sql: String) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: nil)
    }
    func updateCell(tablePath: [String], primaryKey: [(column: String, value: String)], column: String, newValue: String?) async throws {}
    func generateUpdateSQL(tablePath: [String], primaryKey: [(column: String, value: String)], column: String, newValue: String?) -> String { "" }
    func generateInsertSQL(tablePath: [String], columns: [String], values: [String?]) -> String { "" }
    func generateDeleteSQL(tablePath: [String], primaryKey: [(column: String, value: String)]) -> String { "" }
    func generateDropElementSQL(path: [String], elementName: String) -> String { "" }
    func creatableChildLabel(path: [String]) -> String? { nil }
    func createFormFields(path: [String]) -> [CreateField] { [] }
    func generateCreateChildSQL(path: [String], values: [String: String]) -> String? { nil }
    func isDeletable(path: [String]) -> Bool { false }
    func generateDropSQL(path: [String]) -> String? { nil }
    func structurePath(for tablePath: [String]) -> [String]? { nil }
    func fetchCompletionSchema(database: String) async throws -> CompletionSchema { .empty }
    func fetchServerVersion(database: String) async throws -> String? { nil }
}
