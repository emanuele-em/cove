import Foundation

struct PendingEdit {
    let row: Int
    let col: Int
    let newValue: String?
}

@Observable
final class TableState {
    var columns: [ColumnInfo]
    var rows: [[String?]]
    var totalCount: UInt64?
    var pageSize: UInt32 = 50
    var offset: UInt32 = 0
    var sortColumn: String?
    var sortDirection: SortDirection = .asc
    var tablePath: [String]
    var selectedRow: Int?
    var selectedColumn: Int?
    var pendingEdits: [PendingEdit] = []
    var pendingNewRows: Set<Int> = []
    var pendingDeletes: Set<Int> = []
    private(set) var cachedColWidths: [CGFloat]

    init(tablePath: [String], result: QueryResult) {
        self.columns = result.columns
        self.rows = result.rows
        self.totalCount = result.totalCount
        self.tablePath = tablePath
        self.cachedColWidths = Self.computeWidths(columns: result.columns, rows: result.rows)
    }

    func updateData(_ result: QueryResult) {
        columns = result.columns
        rows = result.rows
        totalCount = result.totalCount
        selectedRow = nil
        selectedColumn = nil
        cachedColWidths = Self.computeWidths(columns: result.columns, rows: result.rows)
    }

    func discardEdits() {
        for idx in pendingNewRows.sorted().reversed() {
            rows.remove(at: idx)
        }
        pendingNewRows.removeAll()
        pendingDeletes.removeAll()
        pendingEdits.removeAll()
        selectedRow = nil
        selectedColumn = nil
        cachedColWidths = Self.computeWidths(columns: columns, rows: rows)
    }

    var selectedCellValue: String? {
        guard let row = selectedRow, let col = selectedColumn,
              row < rows.count, col < columns.count else { return nil }
        return effectiveValue(row: row, col: col)
    }

    func selectUp() {
        guard !rows.isEmpty else { return }
        if let row = selectedRow {
            selectedRow = max(row - 1, 0)
        } else {
            selectedRow = 0
        }
    }

    func selectDown() {
        guard !rows.isEmpty else { return }
        if let row = selectedRow {
            selectedRow = min(row + 1, rows.count - 1)
        } else {
            selectedRow = 0
        }
    }

    func selectLeft() {
        guard !columns.isEmpty else { return }
        if let col = selectedColumn {
            selectedColumn = max(col - 1, 0)
        } else {
            selectedColumn = 0
        }
    }

    func selectRight() {
        guard !columns.isEmpty else { return }
        if let col = selectedColumn {
            selectedColumn = min(col + 1, columns.count - 1)
        } else {
            selectedColumn = 0
        }
    }

    func tabForward() {
        guard !columns.isEmpty, !rows.isEmpty else { return }
        let col = selectedColumn ?? 0
        let row = selectedRow ?? 0
        if col < columns.count - 1 {
            selectedColumn = col + 1
            selectedRow = row
        } else if row < rows.count - 1 {
            selectedColumn = 0
            selectedRow = row + 1
        }
    }

    func tabBackward() {
        guard !columns.isEmpty, !rows.isEmpty else { return }
        let col = selectedColumn ?? 0
        let row = selectedRow ?? 0
        if col > 0 {
            selectedColumn = col - 1
            selectedRow = row
        } else if row > 0 {
            selectedColumn = columns.count - 1
            selectedRow = row - 1
        }
    }

    var hasPendingEdits: Bool {
        !pendingEdits.isEmpty || !pendingNewRows.isEmpty || !pendingDeletes.isEmpty
    }

    func effectiveValue(row: Int, col: Int) -> String? {
        if let edit = pendingEdits.last(where: { $0.row == row && $0.col == col }) {
            return edit.newValue
        }
        return rows[row][col]
    }

    func hasEdit(row: Int, col: Int) -> Bool {
        pendingEdits.contains { $0.row == row && $0.col == col }
    }

    func hasEditInRow(_ row: Int) -> Bool {
        pendingEdits.contains { $0.row == row }
    }

    func isNewRow(_ row: Int) -> Bool {
        pendingNewRows.contains(row)
    }

    func isDeletedRow(_ row: Int) -> Bool {
        pendingDeletes.contains(row)
    }

    func addNewRow() -> Int {
        let newRow = Array(repeating: nil as String?, count: columns.count)
        rows.append(newRow)
        let idx = rows.count - 1
        pendingNewRows.insert(idx)
        return idx
    }

    func toggleDelete(_ row: Int) {
        if pendingDeletes.contains(row) {
            pendingDeletes.remove(row)
        } else {
            pendingDeletes.insert(row)
        }
    }

    private static func computeWidths(columns: [ColumnInfo], rows: [[String?]]) -> [CGFloat] {
        let charWidth: CGFloat = 7.5
        let pad: CGFloat = 24
        let minW: CGFloat = 60
        let maxW: CGFloat = 360

        return columns.enumerated().map { colIdx, col in
            let headerLen = col.name.count
            let maxDataLen = rows.map { row in
                row[colIdx]?.count ?? 4
            }.max() ?? 0
            let chars = CGFloat(max(headerLen, maxDataLen))
            return min(max(chars * charWidth + pad, minW), maxW)
        }
    }

    var pageInfo: String {
        let currentPage = offset / pageSize + 1
        let totalPages = totalCount.map { UInt32(($0 + UInt64(pageSize) - 1) / UInt64(pageSize)) } ?? 1
        let from = offset + 1
        let to = totalCount.map { min(offset + pageSize, UInt32($0)) } ?? (offset + UInt32(rows.count))
        let totalStr = totalCount.map { " of \($0)" } ?? ""
        return "Rows \(from)-\(to)\(totalStr)  Page \(currentPage)/\(totalPages)"
    }

    var hasPrev: Bool { offset > 0 }

    var hasNext: Bool {
        let currentPage = offset / pageSize + 1
        let totalPages = totalCount.map { UInt32(($0 + UInt64(pageSize) - 1) / UInt64(pageSize)) } ?? 1
        return currentPage < totalPages
    }

    func sortIndicator(for colName: String) -> String {
        guard sortColumn == colName else { return "" }
        return sortDirection == .asc ? "\u{2191}" : "\u{2193}"
    }
}
