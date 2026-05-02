import XCTest
@testable import Cove

final class TableStateTests: XCTestCase {

    private func makeState(rows: Int = 5, cols: Int = 3) -> TableState {
        let columns = (0..<cols).map { ColumnInfo(name: "col\($0)", typeName: "text", isPrimaryKey: $0 == 0) }
        let rowData = (0..<rows).map { row in
            (0..<cols).map { col -> String? in "r\(row)c\(col)" }
        }
        let result = QueryResult(columns: columns, rows: rowData, rowsAffected: nil, totalCount: UInt64(rows))
        return TableState(tablePath: ["db", "public", "Tables", "test"], result: result)
    }

    // MARK: - selectUp / selectDown

    func testSelectDownFromNil() {
        let state = makeState()
        state.selectDown()
        XCTAssertEqual(state.selectedRow, 0)
    }

    func testSelectDown() {
        let state = makeState()
        state.selectedRow = 2
        state.selectDown()
        XCTAssertEqual(state.selectedRow, 3)
    }

    func testSelectDownClampsToLastRow() {
        let state = makeState()
        state.selectedRow = 4
        state.selectDown()
        XCTAssertEqual(state.selectedRow, 4)
    }

    func testSelectUpFromNil() {
        let state = makeState()
        state.selectUp()
        XCTAssertEqual(state.selectedRow, 0)
    }

    func testSelectUp() {
        let state = makeState()
        state.selectedRow = 2
        state.selectUp()
        XCTAssertEqual(state.selectedRow, 1)
    }

    func testSelectUpClampsToZero() {
        let state = makeState()
        state.selectedRow = 0
        state.selectUp()
        XCTAssertEqual(state.selectedRow, 0)
    }

    // MARK: - selectLeft / selectRight

    func testSelectRightFromNil() {
        let state = makeState()
        state.selectRight()
        XCTAssertEqual(state.selectedColumn, 0)
    }

    func testSelectRight() {
        let state = makeState()
        state.selectedColumn = 1
        state.selectRight()
        XCTAssertEqual(state.selectedColumn, 2)
    }

    func testSelectRightClampsToLastColumn() {
        let state = makeState()
        state.selectedColumn = 2
        state.selectRight()
        XCTAssertEqual(state.selectedColumn, 2)
    }

    func testSelectLeftFromNil() {
        let state = makeState()
        state.selectLeft()
        XCTAssertEqual(state.selectedColumn, 0)
    }

    func testSelectLeftClampsToZero() {
        let state = makeState()
        state.selectedColumn = 0
        state.selectLeft()
        XCTAssertEqual(state.selectedColumn, 0)
    }

    // MARK: - tabForward / tabBackward

    func testTabForwardMovesColumn() {
        let state = makeState()
        state.selectedRow = 0
        state.selectedColumn = 0
        state.tabForward()
        XCTAssertEqual(state.selectedColumn, 1)
        XCTAssertEqual(state.selectedRow, 0)
    }

    func testTabForwardWrapsToNextRow() {
        let state = makeState()
        state.selectedRow = 0
        state.selectedColumn = 2 // last column
        state.tabForward()
        XCTAssertEqual(state.selectedColumn, 0)
        XCTAssertEqual(state.selectedRow, 1)
    }

    func testTabForwardStaysAtEnd() {
        let state = makeState()
        state.selectedRow = 4 // last row
        state.selectedColumn = 2 // last column
        state.tabForward()
        XCTAssertEqual(state.selectedColumn, 2)
        XCTAssertEqual(state.selectedRow, 4)
    }

    func testTabBackwardMovesColumn() {
        let state = makeState()
        state.selectedRow = 0
        state.selectedColumn = 2
        state.tabBackward()
        XCTAssertEqual(state.selectedColumn, 1)
        XCTAssertEqual(state.selectedRow, 0)
    }

    func testTabBackwardWrapsToPreviousRow() {
        let state = makeState()
        state.selectedRow = 1
        state.selectedColumn = 0 // first column
        state.tabBackward()
        XCTAssertEqual(state.selectedColumn, 2) // last column of previous row
        XCTAssertEqual(state.selectedRow, 0)
    }

    func testTabBackwardStaysAtStart() {
        let state = makeState()
        state.selectedRow = 0
        state.selectedColumn = 0
        state.tabBackward()
        XCTAssertEqual(state.selectedColumn, 0)
        XCTAssertEqual(state.selectedRow, 0)
    }

    // MARK: - addNewRow

    func testAddNewRow() {
        let state = makeState()
        let initialCount = state.rows.count
        let idx = state.addNewRow()

        XCTAssertEqual(idx, initialCount)
        XCTAssertEqual(state.rows.count, initialCount + 1)
        XCTAssertTrue(state.isNewRow(idx))
        // New row should have nil values
        XCTAssertTrue(state.rows[idx].allSatisfy { $0 == nil })
    }

    // MARK: - toggleDelete

    func testToggleDelete() {
        let state = makeState()
        XCTAssertFalse(state.isDeletedRow(2))

        state.toggleDelete(2)
        XCTAssertTrue(state.isDeletedRow(2))

        state.toggleDelete(2)
        XCTAssertFalse(state.isDeletedRow(2))
    }

    // MARK: - effectiveValue

    func testEffectiveValueReturnsOriginal() {
        let state = makeState()
        XCTAssertEqual(state.effectiveValue(row: 0, col: 0), "r0c0")
    }

    func testEffectiveValueReturnsEditedValue() {
        let state = makeState()
        state.pendingEdits.append(PendingEdit(row: 0, col: 0, newValue: "edited"))
        XCTAssertEqual(state.effectiveValue(row: 0, col: 0), "edited")
    }

    func testEffectiveValueReturnsLatestEdit() {
        let state = makeState()
        state.pendingEdits.append(PendingEdit(row: 0, col: 0, newValue: "first"))
        state.pendingEdits.append(PendingEdit(row: 0, col: 0, newValue: "second"))
        XCTAssertEqual(state.effectiveValue(row: 0, col: 0), "second")
    }

    func testEffectiveValueNilEdit() {
        let state = makeState()
        state.pendingEdits.append(PendingEdit(row: 0, col: 0, newValue: nil))
        XCTAssertNil(state.effectiveValue(row: 0, col: 0))
    }

    // MARK: - discardEdits

    func testDiscardEdits() {
        let state = makeState()
        let idx = state.addNewRow()
        state.pendingEdits.append(PendingEdit(row: 0, col: 0, newValue: "edited"))
        state.toggleDelete(1)

        state.discardEdits()

        XCTAssertTrue(state.pendingEdits.isEmpty)
        XCTAssertTrue(state.pendingNewRows.isEmpty)
        XCTAssertTrue(state.pendingDeletes.isEmpty)
        XCTAssertNil(state.selectedRow)
        XCTAssertNil(state.selectedColumn)
        // New row should have been removed
        XCTAssertEqual(state.rows.count, 5)
    }

    // MARK: - hasEdit

    func testHasEdit() {
        let state = makeState()
        XCTAssertFalse(state.hasEdit(row: 0, col: 0))
        state.pendingEdits.append(PendingEdit(row: 0, col: 0, newValue: "x"))
        XCTAssertTrue(state.hasEdit(row: 0, col: 0))
        XCTAssertFalse(state.hasEdit(row: 0, col: 1))
    }

    // MARK: - Pagination

    func testPageInfo() {
        let state = makeState()
        state.pageSize = 50
        state.offset = 0
        let info = state.pageInfo
        XCTAssertTrue(info.contains("Rows 1-"))
        XCTAssertTrue(info.contains("Page 1/"))
    }

    func testHasPrev() {
        let state = makeState()
        state.offset = 0
        XCTAssertFalse(state.hasPrev)
        state.offset = 50
        XCTAssertTrue(state.hasPrev)
    }

    // MARK: - Empty state

    func testNavigationOnEmptyState() {
        let result = QueryResult(columns: [], rows: [], rowsAffected: nil, totalCount: 0)
        let state = TableState(tablePath: ["db", "public", "Tables", "empty"], result: result)

        state.selectUp()
        XCTAssertNil(state.selectedRow)

        state.selectDown()
        XCTAssertNil(state.selectedRow)

        state.selectLeft()
        XCTAssertNil(state.selectedColumn)

        state.selectRight()
        XCTAssertNil(state.selectedColumn)
    }

    func testMutationTablePathUsesTablePathForNormalTable() {
        let state = makeState()
        XCTAssertEqual(state.mutationTablePath, ["db", "public", "Tables", "test"])
    }

    func testMutationTablePathUsesEditablePathForQueryResult() {
        let columns = [
            ColumnInfo(name: "alias_id", typeName: "uuid", isPrimaryKey: true, sourceColumnName: "id"),
            ColumnInfo(name: "name", typeName: "text", isPrimaryKey: false),
        ]
        let result = QueryResult(
            columns: columns,
            rows: [["1", "Alice"]],
            rowsAffected: nil,
            totalCount: nil,
            editableTablePath: ["db", "public", "Tables", "users"]
        )
        let state = TableState(tablePath: [], result: result)

        XCTAssertEqual(state.mutationTablePath, ["db", "public", "Tables", "users"])
        XCTAssertEqual(state.columns[0].updateColumnName, "id")
        XCTAssertEqual(state.columns[1].updateColumnName, "name")
    }

    func testSortIndicator() {
        let state = makeState()
        XCTAssertEqual(state.sortIndicator(for: "col0"), "")

        state.sortColumn = "col0"
        state.sortDirection = .asc
        XCTAssertEqual(state.sortIndicator(for: "col0"), "\u{2191}")

        state.sortDirection = .desc
        XCTAssertEqual(state.sortIndicator(for: "col0"), "\u{2193}")

        XCTAssertEqual(state.sortIndicator(for: "col1"), "")
    }
}
