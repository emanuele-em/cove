import XCTest
@testable import Cove

final class QueryStateTests: XCTestCase {

    func testSingleBlockReturnsFullText() {
        let state = QueryState()
        state.text = "SELECT * FROM users"
        state.selectedRange = NSRange(location: 5, length: 0)

        let range = state.runnableRange
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, state.text.count)
    }

    func testTwoBlocksCursorInFirst() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 3, length: 0) // cursor in "SELECT 1"

        let sql = state.runnableSQL
        XCTAssertEqual(sql, "SELECT 1")
    }

    func testTwoBlocksCursorInSecond() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 14, length: 0) // cursor in "SELECT 2"

        let sql = state.runnableSQL
        XCTAssertEqual(sql, "SELECT 2")
    }

    func testSelectionOverridesBlockDetection() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 0, length: 8) // "SELECT 1" selected

        let range = state.runnableRange
        XCTAssertEqual(range, NSRange(location: 0, length: 8))
    }

    func testEmptyTextReturnsEmptyRange() {
        let state = QueryState()
        state.text = ""
        state.selectedRange = NSRange(location: 0, length: 0)

        let range = state.runnableRange
        XCTAssertEqual(range.length, 0)
    }

    func testWhitespaceTrimming() {
        let state = QueryState()
        state.text = "  SELECT 1  "
        state.selectedRange = NSRange(location: 5, length: 0)

        let sql = state.runnableSQL
        XCTAssertEqual(sql, "SELECT 1")
    }

    func testThreeBlocks() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2\n\nSELECT 3"
        state.selectedRange = NSRange(location: 14, length: 0) // cursor in "SELECT 2"

        let sql = state.runnableSQL
        XCTAssertEqual(sql, "SELECT 2")
    }

    func testCursorAtEnd() {
        let state = QueryState()
        state.text = "SELECT 1"
        state.selectedRange = NSRange(location: 8, length: 0)

        let sql = state.runnableSQL
        XCTAssertEqual(sql, "SELECT 1")
    }

    func testReplaceRunnableSQLReplacesCurrentBlock() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 14, length: 0)

        state.replaceRunnableSQL(with: "SELECT 3")

        XCTAssertEqual(state.text, "SELECT 1\n\nSELECT 3")
        XCTAssertEqual(state.selectedRange.location, "SELECT 1\n\nSELECT 3".count)
    }

    func testReplaceSelectedSQL() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 0, length: 8)

        state.replaceRunnableSQL(with: "SELECT 10")

        XCTAssertEqual(state.text, "SELECT 10\n\nSELECT 2")
    }

    func testAppendSQLAddsNewBlock() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 0, length: 0)

        state.appendSQL("SELECT 3")

        XCTAssertEqual(state.text, "SELECT 1\n\nSELECT 2\n\nSELECT 3")
        XCTAssertEqual(state.selectedRange.location, state.text.utf16.count)
    }

    func testAppendSQLUsesEmptyEditor() {
        let state = QueryState()
        state.text = "  \n"

        state.appendSQL("SELECT 1")

        XCTAssertEqual(state.text, "SELECT 1")
        XCTAssertEqual(state.selectedRange.location, state.text.utf16.count)
    }

    func testInsertSQLOnBlankSeparatorLinePreservesQueryBlocks() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"

        let range = state.insertSQL("SELECT 3", at: 9)

        XCTAssertEqual(state.text, "SELECT 1\n\nSELECT 3\n\nSELECT 2")
        XCTAssertEqual(range, NSRange(location: 10, length: 8))
        XCTAssertEqual(state.runnableSQL, "SELECT 3")
    }

    func testAgentModeTargetUsesBlankSeparatorLine() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 9, length: 0)

        let range = state.agentModeTargetRangeAtCursor

        XCTAssertEqual(range, NSRange(location: 9, length: 0))
    }

    func testAgentModeTargetUsesCurrentBlockWhenCursorIsInQuery() {
        let state = QueryState()
        state.text = "SELECT 1\n\nSELECT 2"
        state.selectedRange = NSRange(location: 14, length: 0)

        let range = state.agentModeTargetRangeAtCursor

        XCTAssertEqual(state.sql(in: range), "SELECT 2")
    }

    func testRunnableRangeUsesUTF16Offsets() {
        let state = QueryState()
        let firstQuery = "/* 😀 */ SELECT 1"
        state.text = "\(firstQuery)\n\nSELECT 2"
        state.selectedRange = NSRange(location: ("/* 😀 */" as NSString).length, length: 0)

        XCTAssertEqual(state.runnableSQL, firstQuery)
    }
}
