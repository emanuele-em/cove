import Foundation
import AppKit

enum ContentMode {
    case empty
    case table
    case query
}

enum TableTab {
    case data
    case structure
}

@Observable
@MainActor
final class AppState {
    var connection: (any DatabaseBackend)?
    var sshTunnel: SSHTunnel?
    var tree = TreeState()
    var table: TableState?
    var savedConnections: [SavedConnection]
    var activeConnectionIdx: Int?
    var showSidebar = true
    var sidebarWidth: CGFloat = 220
    var showInspector = false
    var showBottomPanel = false
    var queryTable: TableState?
    var contentMode: ContentMode = .empty
    var tableTab: TableTab = .data
    var structureTable: TableState?
    var queryDatabase = ""
    var breadcrumb = ""
    var errorText = ""
    var dialog = DialogState()
    var connectionToDelete: SavedConnection?
    var focusedColumn: Int?
    var showSQLPreview = false
    var connecting = false
    var query = QueryState()
    var savedQueries: [String: String]
    var showCreateSheet = false
    var createSheetLabel = ""
    var createSheetParentPath: [String] = []
    var createSheetFields: [CreateField] = []
    var showTreeAction = false
    var treeActionSQL = ""
    var treeActionDB = ""
    var treeActionRefreshPath: [String] = []

    init() {
        let store = ConnectionStoreIO.load()
        self.savedConnections = store.connections
        self.savedQueries = QueryStoreIO.load()
    }

    // MARK: - Connection

    func openDialog() {
        dialog.reset()
        dialog.visible = true
    }

    func selectConnection(_ idx: Int) {
        saveCurrentQuery()
        activeConnectionIdx = idx
        guard let saved = savedConnections[safe: idx] else { return }
        let config = ConnectionConfig(
            backend: saved.backend, host: saved.host, port: saved.port,
            user: saved.user, password: saved.password, database: saved.database,
            sshTunnel: saved.sshTunnelConfig
        )
        Task {
            await performConnect(config: config)
            saveSession()
        }
    }

    func dialogConnect() {
        saveCurrentQuery()
        dialog.connecting = true
        dialog.error = ""
        connecting = true

        let saved = SavedConnection(
            name: dialog.name,
            backend: dialog.backend,
            host: dialog.host,
            port: dialog.port,
            user: dialog.user,
            password: dialog.password,
            database: dialog.database,
            colorHex: dialog.colorHex,
            sshEnabled: dialog.sshEnabled ? true : nil,
            sshHost: dialog.sshEnabled ? dialog.sshHost : nil,
            sshPort: dialog.sshEnabled ? dialog.sshPort : nil,
            sshUser: dialog.sshEnabled ? dialog.sshUser : nil,
            sshAuthMethod: dialog.sshEnabled ? dialog.sshAuthMethod : nil,
            sshPassword: dialog.sshEnabled ? dialog.sshPassword : nil,
            sshPrivateKeyPath: dialog.sshEnabled ? dialog.sshPrivateKeyPath : nil,
            sshPassphrase: dialog.sshEnabled ? dialog.sshPassphrase : nil
        )
        let config = ConnectionConfig(
            backend: saved.backend, host: saved.host, port: saved.port,
            user: saved.user, password: saved.password, database: saved.database,
            sshTunnel: saved.sshTunnelConfig
        )

        Task {
            do {
                await closeTunnel()
                let (conn, tunnel) = try await morfeoConnect(config: config)
                self.connection = conn
                self.sshTunnel = tunnel
                self.savedConnections.append(saved)
                self.activeConnectionIdx = self.savedConnections.count - 1
                self.tree.reset()
                self.table = nil
                self.contentMode = .empty
                self.errorText = ""
                self.dialog.visible = false

                ConnectionStoreIO.save(ConnectionStore(connections: self.savedConnections))
                self.updateBreadcrumb()
                await self.loadChildren(path: [])
                self.saveSession()
            } catch {
                self.dialog.error = error.localizedDescription
            }
            self.dialog.connecting = false
            self.connecting = false
        }
    }

    func dialogTest() {
        dialog.testing = true
        dialog.testResult = nil
        dialog.error = ""

        let sshTunnelConfig: SSHTunnelConfig? = dialog.sshEnabled
            ? SSHTunnelConfig(
                sshHost: dialog.sshHost, sshPort: dialog.sshPort,
                sshUser: dialog.sshUser, authMethod: dialog.sshAuthMethod,
                sshPassword: dialog.sshPassword, privateKeyPath: dialog.sshPrivateKeyPath,
                passphrase: dialog.sshPassphrase)
            : nil
        let config = ConnectionConfig(
            backend: dialog.backend, host: dialog.host, port: dialog.port,
            user: dialog.user, password: dialog.password, database: dialog.database,
            sshTunnel: sshTunnelConfig
        )

        Task {
            do {
                let (_, tunnel) = try await withThrowingTaskGroup(of: (any DatabaseBackend, SSHTunnel?).self) { group in
                    group.addTask {
                        try await morfeoConnect(config: config)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(15))
                        throw CancellationError()
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                await tunnel?.close()
                self.dialog.testResult = (success: true, message: "Connection successful.")
            } catch is CancellationError {
                self.dialog.testResult = (success: false, message: "Connection timed out after 15 seconds.")
            } catch {
                self.dialog.testResult = (success: false, message: error.localizedDescription)
            }
            self.dialog.testing = false
        }
    }

    func dialogCancel() {
        dialog.visible = false
    }

    func openEditDialog(for conn: SavedConnection) {
        dialog.reset()
        dialog.editingConnectionId = conn.id
        dialog.name = conn.name
        dialog.backend = conn.backend
        dialog.host = conn.host
        dialog.port = conn.port
        dialog.user = conn.user
        dialog.password = conn.password
        dialog.database = conn.database
        dialog.colorHex = conn.colorHex ?? MorfeoTheme.accentHex
        dialog.sshEnabled = conn.sshEnabled ?? false
        dialog.sshHost = conn.sshHost ?? ""
        dialog.sshPort = conn.sshPort ?? "22"
        dialog.sshUser = conn.sshUser ?? ""
        dialog.sshAuthMethod = conn.sshAuthMethod ?? .password
        dialog.sshPassword = conn.sshPassword ?? ""
        dialog.sshPrivateKeyPath = conn.sshPrivateKeyPath ?? ""
        dialog.sshPassphrase = conn.sshPassphrase ?? ""
        dialog.visible = true
    }

    func dialogSaveEdit() {
        guard let editId = dialog.editingConnectionId,
              let idx = savedConnections.firstIndex(where: { $0.id == editId }) else { return }

        savedConnections[idx].name = dialog.name
        savedConnections[idx].backend = dialog.backend
        savedConnections[idx].host = dialog.host
        savedConnections[idx].port = dialog.port
        savedConnections[idx].user = dialog.user
        savedConnections[idx].password = dialog.password
        savedConnections[idx].database = dialog.database
        savedConnections[idx].colorHex = dialog.colorHex
        savedConnections[idx].sshEnabled = dialog.sshEnabled ? true : nil
        savedConnections[idx].sshHost = dialog.sshEnabled ? dialog.sshHost : nil
        savedConnections[idx].sshPort = dialog.sshEnabled ? dialog.sshPort : nil
        savedConnections[idx].sshUser = dialog.sshEnabled ? dialog.sshUser : nil
        savedConnections[idx].sshAuthMethod = dialog.sshEnabled ? dialog.sshAuthMethod : nil
        savedConnections[idx].sshPassword = dialog.sshEnabled ? dialog.sshPassword : nil
        savedConnections[idx].sshPrivateKeyPath = dialog.sshEnabled ? dialog.sshPrivateKeyPath : nil
        savedConnections[idx].sshPassphrase = dialog.sshEnabled ? dialog.sshPassphrase : nil

        ConnectionStoreIO.save(ConnectionStore(connections: savedConnections))
        dialog.visible = false

        if activeConnectionIdx == idx {
            selectConnection(idx)
        }
    }

    func requestDeleteConnection(_ conn: SavedConnection) {
        connectionToDelete = conn
    }

    func confirmDeleteConnection() {
        guard let conn = connectionToDelete else { return }
        guard let idx = savedConnections.firstIndex(where: { $0.id == conn.id }) else {
            connectionToDelete = nil
            return
        }

        if activeConnectionIdx == idx {
            Task { await closeTunnel() }
            connection = nil
            tree.reset()
            table = nil
            contentMode = .empty
            errorText = ""
            breadcrumb = ""
            activeConnectionIdx = nil
        } else if let active = activeConnectionIdx, idx < active {
            activeConnectionIdx = active - 1
        }

        savedConnections.remove(at: idx)
        ConnectionStoreIO.save(ConnectionStore(connections: savedConnections))
        connectionToDelete = nil
    }

    private func performConnect(config: ConnectionConfig) async {
        connecting = true
        await closeTunnel()
        do {
            let (conn, tunnel) = try await morfeoConnect(config: config)
            self.connection = conn
            self.sshTunnel = tunnel
            self.tree.reset()
            self.table = nil
            self.contentMode = .empty
            self.errorText = ""
            self.updateBreadcrumb()
            await self.loadChildren(path: [])
        } catch {
            self.errorText = error.localizedDescription
        }
        connecting = false
    }

    private func closeTunnel() async {
        await sshTunnel?.close()
        sshTunnel = nil
    }

    // MARK: - Tree

    func treeToggleExpansion(_ index: Int) {
        guard let path = tree.pathForIndex(index),
              tree.isExpandableAt(index) else { return }
        treeToggleExpansion(path: path)
    }

    func treeToggleExpansion(path: [String]) {
        if tree.expanded.contains(path) {
            tree.expanded.remove(path)
            tree.rebuildFlat()
        } else {
            tree.expanded.insert(path)
            if tree.children[path] == nil {
                Task { await loadChildren(path: path) }
            } else {
                tree.rebuildFlat()
            }
        }

        saveSession()
    }

    func treeSelectNode(_ index: Int) {
        guard let path = tree.pathForIndex(index) else { return }
        treeSelectNode(path: path)
    }

    func treeSelectNode(path: [String]) {
        tree.selected = path
        updateBreadcrumb()
        tree.rebuildFlat()

        if connection?.isDataBrowsable(path: path) == true {
            Task { await loadTableData(path: path, offset: 0) }
        } else if path.count >= 2 {
            Task { await loadNodeDetails(path: path) }
        }

        saveSession()
    }

    func promptCreateChild(parentPath: [String]) {
        guard let conn = connection,
              let label = conn.creatableChildLabel(path: parentPath) else { return }
        createSheetLabel = label
        createSheetParentPath = parentPath
        createSheetFields = conn.createFormFields(path: parentPath)
        showCreateSheet = true
    }

    func executeCreateChild(values: [String: String]) {
        guard let conn = connection else { return }
        let parentPath = createSheetParentPath
        guard let sql = conn.generateCreateChildSQL(path: parentPath, values: values) else { return }
        showCreateSheet = false
        let db = parentPath.first ?? ""
        Task {
            do {
                _ = try await conn.executeQuery(database: db, sql: sql)
                tree.children.removeValue(forKey: parentPath)
                await loadChildren(path: parentPath)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    func promptDeleteNode(path: [String]) {
        guard let conn = connection,
              let sql = conn.generateDropSQL(path: path) else { return }
        treeActionSQL = sql
        // For DROP DATABASE, run on a different connection (empty = default)
        treeActionDB = path.count == 1 ? "" : (path.first ?? "")
        treeActionRefreshPath = Array(path.dropLast())
        showTreeAction = true
    }

    func executeTreeAction() {
        guard let conn = connection, !treeActionSQL.isEmpty else { return }
        let sql = treeActionSQL
        let db = treeActionDB
        let refreshPath = treeActionRefreshPath
        showTreeAction = false
        Task {
            do {
                _ = try await conn.executeQuery(database: db, sql: sql)
                tree.children.removeValue(forKey: refreshPath)
                await loadChildren(path: refreshPath)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    func loadChildren(path: [String]) async {
        guard let conn = connection else { return }
        tree.loading.insert(path)
        tree.rebuildFlat()

        do {
            let nodes = try await conn.listChildren(path: path)
            tree.loading.remove(path)
            tree.children[path] = nodes
        } catch {
            tree.loading.remove(path)
            errorText = error.localizedDescription
        }
        tree.rebuildFlat()
    }

    // MARK: - Query Toggle

    func toggleQuery() {
        if contentMode == .query {
            saveCurrentQuery()
            if let path = tree.selected {
                if connection?.isDataBrowsable(path: path) == true {
                    Task { await loadTableData(path: path, offset: 0) }
                } else if path.count >= 3 {
                    Task { await loadNodeDetails(path: path) }
                } else {
                    contentMode = .empty
                }
            } else {
                contentMode = .empty
            }
        } else {
            queryDatabase = tree.selected?.first ?? ""
            loadCurrentQuery()
            contentMode = .query
        }
    }

    func saveCurrentQuery() {
        guard let idx = activeConnectionIdx,
              let conn = savedConnections[safe: idx] else { return }
        let key = conn.id.uuidString
        if query.text.isEmpty {
            savedQueries.removeValue(forKey: key)
        } else {
            savedQueries[key] = query.text
        }
        QueryStoreIO.save(savedQueries)
    }

    private func loadCurrentQuery() {
        guard let idx = activeConnectionIdx,
              let conn = savedConnections[safe: idx] else { return }
        query.text = savedQueries[conn.id.uuidString] ?? ""
        query.selectedRange = NSRange(location: 0, length: 0)
        query.error = ""
        query.status = ""
        query.result = nil
    }

    func loadNodeDetails(path: [String]) async {
        guard let conn = connection else { return }
        do {
            let data = try await conn.fetchNodeDetails(path: path)
            errorText = ""
            if data.columns.isEmpty {
                contentMode = .empty
            } else {
                table = TableState(tablePath: path, result: data)
                contentMode = .table
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Table Tab

    var isDataGroupTable: Bool {
        guard let table else { return false }
        return connection?.isDataBrowsable(path: table.tablePath) == true
    }

    var hasStructureTab: Bool {
        guard let table else { return false }
        return isDataGroupTable && connection?.structurePath(for: table.tablePath) != nil
    }

    var isEditableTable: Bool {
        guard let table else { return false }
        return connection?.isEditable(path: table.tablePath) == true
            && table.columns.contains(where: \.isPrimaryKey)
    }

    var isEditableStructure: Bool {
        guard let table else { return false }
        return connection?.isStructureEditable(path: table.tablePath) == true
    }

    func tableTabChanged(_ tab: TableTab) {
        tableTab = tab
        if tab == .structure, structureTable == nil {
            loadTableStructure()
        }
    }

    func loadTableStructure() {
        guard let table, let conn = connection else { return }
        let path = table.tablePath
        guard let structurePath = conn.structurePath(for: path) else { return }

        Task {
            do {
                let data = try await conn.fetchNodeDetails(path: structurePath)
                self.structureTable = TableState(tablePath: path, result: data)
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Table

    func loadTableData(path: [String], offset: UInt32) async {
        guard let conn = connection else { return }
        let sortCol = table?.sortColumn
        let sortDir = table?.sortDirection ?? .asc
        let limit = table?.pageSize ?? 50

        let sort: (column: String, direction: SortDirection)? = sortCol.map { ($0, sortDir) }

        do {
            let data = try await conn.fetchTableData(path: path, limit: limit, offset: offset, sort: sort)
            errorText = ""
            if let existing = table, existing.tablePath == path {
                existing.updateData(data)
            } else {
                table = TableState(tablePath: path, result: data)
                tableTab = .data
                structureTable = nil
            }
            contentMode = .table
        } catch {
            errorText = error.localizedDescription
        }
    }

    func tableSortClicked(_ colIdx: Int) {
        guard let table, connection?.isDataBrowsable(path: table.tablePath) == true else { return }
        guard let colName = table.columns[safe: colIdx]?.name else { return }

        if table.sortColumn == colName {
            table.sortDirection = table.sortDirection == .asc ? .desc : .asc
        } else {
            table.sortColumn = colName
            table.sortDirection = .asc
        }
        let path = table.tablePath
        let offset = table.offset
        Task { await loadTableData(path: path, offset: offset) }
    }

    func tableRowClicked(row: Int) {
        table?.selectedRow = row
    }

    func tableCellDoubleClicked(row: Int, col: Int) {
        guard let table else { return }
        table.selectedRow = row
        table.selectedColumn = col
        focusedColumn = col
        showInspector = true
    }

    func inspectorFieldConfirmed(col: Int, value: String) {
        guard let table else { return }
        guard let row = table.selectedRow else { return }
        let newValue = value.isEmpty ? nil : value
        table.pendingEdits.append(PendingEdit(row: row, col: col, newValue: newValue))
    }

    func addRow() {
        guard let table, isEditableTable else { return }
        let rowIdx = table.addNewRow()
        table.selectedRow = rowIdx
        focusedColumn = 0
        showInspector = true
    }

    func deleteSelectedRow() {
        guard let table, let row = table.selectedRow else { return }
        if table.isNewRow(row) {
            table.pendingNewRows.remove(row)
            table.pendingEdits = table.pendingEdits.compactMap { edit in
                if edit.row == row { return nil }
                if edit.row > row {
                    return PendingEdit(row: edit.row - 1, col: edit.col, newValue: edit.newValue)
                }
                return edit
            }
            table.rows.remove(at: row)
            table.pendingNewRows = Set(table.pendingNewRows.map { $0 > row ? $0 - 1 : $0 })
            table.pendingDeletes = Set(table.pendingDeletes.map { $0 > row ? $0 - 1 : $0 })
            table.selectedRow = nil
        } else {
            guard isEditableTable || isEditableStructure else { return }
            table.toggleDelete(row)
        }
    }

    func generateSQLPreview() -> String {
        if isEditableStructure { return generateStructureSQLPreview() }
        guard let table, let conn = connection else { return "" }
        let columns = table.columns
        let rows = table.rows
        let pkCols = columns.enumerated().filter { $0.element.isPrimaryKey }.map(\.offset)

        var statements: [String] = []

        // INSERTs for new rows
        for rowIdx in table.pendingNewRows.sorted() {
            var colEdits: [Int: String?] = [:]
            for edit in table.pendingEdits where edit.row == rowIdx {
                colEdits[edit.col] = edit.newValue
            }
            guard !colEdits.isEmpty else { continue }
            let pairs = colEdits.sorted(by: { $0.key < $1.key })
            let colNames = pairs.map { columns[$0.key].name }
            let values = pairs.map(\.value)
            statements.append(conn.generateInsertSQL(
                tablePath: table.tablePath,
                columns: colNames,
                values: values
            ))
        }

        // UPDATEs for existing rows with edits (not new, not deleted)
        var seen: [String: Int] = [:]
        var deduped: [PendingEdit] = []
        for edit in table.pendingEdits where !table.isNewRow(edit.row) && !table.isDeletedRow(edit.row) {
            let key = "\(edit.row):\(edit.col)"
            if let idx = seen[key] {
                deduped[idx] = edit
            } else {
                seen[key] = deduped.count
                deduped.append(edit)
            }
        }
        for edit in deduped {
            let pk: [(column: String, value: String)] = pkCols.map { i in
                (column: columns[i].name, value: rows[edit.row][i] ?? "")
            }
            statements.append(conn.generateUpdateSQL(
                tablePath: table.tablePath,
                primaryKey: pk,
                column: columns[edit.col].name,
                newValue: edit.newValue
            ))
        }

        // DELETEs for deleted rows
        for rowIdx in table.pendingDeletes.sorted() {
            let pk: [(column: String, value: String)] = pkCols.map { i in
                (column: columns[i].name, value: rows[rowIdx][i] ?? "")
            }
            statements.append(conn.generateDeleteSQL(
                tablePath: table.tablePath,
                primaryKey: pk
            ))
        }

        return statements.joined(separator: ";\n")
    }

    private func generateStructureSQLPreview() -> String {
        guard let table, let conn = connection else { return "" }
        var seen = Set<String>()
        var statements: [String] = []
        for rowIdx in table.pendingDeletes.sorted() {
            guard let name = table.rows[rowIdx].first.flatMap({ $0 }) else { continue }
            guard seen.insert(name).inserted else { continue }
            statements.append(conn.generateDropElementSQL(
                path: table.tablePath,
                elementName: name
            ))
        }
        return statements.joined(separator: ";\n")
    }

    func tableNextPage() {
        guard let table, connection?.isDataBrowsable(path: table.tablePath) == true else { return }
        let newOffset = table.offset + table.pageSize
        table.offset = newOffset
        let path = table.tablePath
        Task { await loadTableData(path: path, offset: newOffset) }
    }

    func tablePrevPage() {
        guard let table, connection?.isDataBrowsable(path: table.tablePath) == true else { return }
        let newOffset = table.offset > table.pageSize ? table.offset - table.pageSize : 0
        table.offset = newOffset
        let path = table.tablePath
        Task { await loadTableData(path: path, offset: newOffset) }
    }

    func tablePageSize(_ size: UInt32) {
        guard let table, connection?.isDataBrowsable(path: table.tablePath) == true else { return }
        table.pageSize = size
        table.offset = 0
        let path = table.tablePath
        Task { await loadTableData(path: path, offset: 0) }
    }

    // MARK: - Header actions

    func refresh() {
        guard let table else { return }
        let path = table.tablePath
        if connection?.isDataBrowsable(path: path) == true {
            if tableTab == .structure {
                structureTable = nil
                loadTableStructure()
            } else {
                let offset = table.offset
                Task { await loadTableData(path: path, offset: offset) }
            }
        } else {
            Task { await loadNodeDetails(path: path) }
        }
    }

    func discardEdits() {
        table?.discardEdits()
        focusedColumn = nil
    }

    func commitEdits() {
        if isEditableStructure { commitStructureEdits(); return }
        guard let table, table.hasPendingEdits else { return }
        guard let conn = connection else { return }

        let tablePath = table.tablePath
        let columns = table.columns
        let rows = table.rows
        let edits = table.pendingEdits
        let pkCols = columns.enumerated().filter { $0.element.isPrimaryKey }.map(\.offset)
        let newRows = table.pendingNewRows
        let deletedRows = table.pendingDeletes

        Task {
            do {
                // INSERTs
                for rowIdx in newRows.sorted() {
                    var colEdits: [Int: String?] = [:]
                    for edit in edits where edit.row == rowIdx {
                        colEdits[edit.col] = edit.newValue
                    }
                    guard !colEdits.isEmpty else { continue }
                    let pairs = colEdits.sorted(by: { $0.key < $1.key })
                    let colNames = pairs.map { columns[$0.key].name }
                    let values = pairs.map(\.value)
                    let sql = conn.generateInsertSQL(
                        tablePath: tablePath,
                        columns: colNames,
                        values: values
                    )
                    _ = try await conn.executeQuery(database: tablePath[0], sql: sql)
                }

                // UPDATEs (deduplicated — keep last edit per row+col)
                var seen: [String: Int] = [:]
                var deduped: [PendingEdit] = []
                for edit in edits where !newRows.contains(edit.row) && !deletedRows.contains(edit.row) {
                    let key = "\(edit.row):\(edit.col)"
                    if let idx = seen[key] {
                        deduped[idx] = edit
                    } else {
                        seen[key] = deduped.count
                        deduped.append(edit)
                    }
                }
                for edit in deduped {
                    let pk: [(column: String, value: String)] = pkCols.map { i in
                        (column: columns[i].name, value: rows[edit.row][i] ?? "")
                    }
                    try await conn.updateCell(
                        tablePath: tablePath,
                        primaryKey: pk,
                        column: columns[edit.col].name,
                        newValue: edit.newValue
                    )
                }

                // DELETEs
                for rowIdx in deletedRows.sorted() {
                    let pk: [(column: String, value: String)] = pkCols.map { i in
                        (column: columns[i].name, value: rows[rowIdx][i] ?? "")
                    }
                    let sql = conn.generateDeleteSQL(
                        tablePath: tablePath,
                        primaryKey: pk
                    )
                    _ = try await conn.executeQuery(database: tablePath[0], sql: sql)
                }

                table.pendingNewRows.removeAll()
                table.pendingDeletes.removeAll()
                table.pendingEdits.removeAll()
                table.selectedRow = nil
                refresh()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func commitStructureEdits() {
        guard let table, table.hasPendingEdits else { return }
        guard let conn = connection else { return }

        let path = table.tablePath
        var seen = Set<String>()
        var sqls: [String] = []
        for rowIdx in table.pendingDeletes.sorted() {
            guard let name = table.rows[rowIdx].first.flatMap({ $0 }) else { continue }
            guard seen.insert(name).inserted else { continue }
            sqls.append(conn.generateDropElementSQL(path: path, elementName: name))
        }

        Task {
            do {
                for sql in sqls {
                    _ = try await conn.executeQuery(database: path[0], sql: sql)
                }
                table.pendingDeletes.removeAll()
                table.selectedRow = nil
                refresh()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Query

    func executeQuery() {
        guard let conn = connection else { return }
        let database = queryDatabase
        let sql = query.runnableSQL
        guard !sql.isEmpty else { return }

        saveCurrentQuery()
        query.executing = true
        query.error = ""
        query.status = ""

        Task {
            do {
                let data = try await conn.executeQuery(database: database, sql: sql)
                query.executing = false
                query.error = ""
                if data.columns.isEmpty {
                    let n = data.rowsAffected ?? 0
                    query.status = "\(n) rows affected"
                    query.result = nil
                    queryTable = nil
                } else {
                    let rowCount = data.rows.count
                    query.status = rowCount > 10_000 ? "Showing 10,000 of \(rowCount) rows" : "\(rowCount) rows"
                    query.result = data
                    queryTable = TableState(tablePath: [], result: data)
                    showBottomPanel = true
                }
            } catch {
                query.executing = false
                query.error = error.localizedDescription
                query.result = nil
                queryTable = nil
            }
        }
    }

    // MARK: - Keyboard Navigation

    func tableEscape() {
        if focusedColumn != nil {
            focusedColumn = nil
        } else if showInspector {
            showInspector = false
        } else if table?.selectedColumn != nil {
            table?.selectedColumn = nil
        } else {
            table?.selectedRow = nil
        }
    }

    func tableEnter() {
        guard table?.selectedRow != nil else { return }
        focusedColumn = table?.selectedColumn ?? 0
        showInspector = true
    }

    func tableCopyCell() {
        guard let table else { return }
        let text: String
        if let cellValue = table.selectedCellValue {
            text = cellValue
        } else if let row = table.selectedRow, row < table.rows.count {
            text = table.rows[row].map { $0 ?? "NULL" }.joined(separator: "\t")
        } else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Session Persistence

    func saveSession() {
        let connId: UUID?
        if let idx = activeConnectionIdx, let conn = savedConnections[safe: idx] {
            connId = conn.id
        } else {
            connId = nil
        }
        let session = SessionState(
            activeConnectionId: connId,
            selectedPath: tree.selected,
            expandedPaths: tree.expanded.isEmpty ? nil : tree.expanded,
            showInspector: showInspector,
            showSidebar: showSidebar,
            sidebarWidth: sidebarWidth
        )
        SessionStoreIO.save(session)
    }

    func restoreSession() async {
        guard connection == nil else { return }
        guard let session = SessionStoreIO.load() else { return }

        showInspector = session.showInspector
        showSidebar = session.showSidebar
        if let w = session.sidebarWidth { sidebarWidth = w }

        guard let connId = session.activeConnectionId,
              let idx = savedConnections.firstIndex(where: { $0.id == connId }) else { return }

        let saved = savedConnections[idx]
        activeConnectionIdx = idx
        connecting = true
        let config = ConnectionConfig(
            backend: saved.backend, host: saved.host, port: saved.port,
            user: saved.user, password: saved.password, database: saved.database,
            sshTunnel: saved.sshTunnelConfig
        )

        do {
            let (conn, tunnel) = try await morfeoConnect(config: config)
            self.connection = conn
            self.sshTunnel = tunnel
            self.tree.reset()
            self.table = nil
            self.contentMode = .empty
            self.errorText = ""
            self.updateBreadcrumb()
            await self.loadChildren(path: [])
        } catch {
            self.errorText = error.localizedDescription
            connecting = false
            return
        }
        connecting = false

        if let expandedPaths = session.expandedPaths {
            let sorted = expandedPaths.sorted { $0.count < $1.count }
            for path in sorted {
                tree.expanded.insert(path)
                if tree.children[path] == nil {
                    await loadChildren(path: path)
                }
            }
        }

        if let targetPath = session.selectedPath {
            for i in 1..<targetPath.count {
                let prefix = Array(targetPath.prefix(i))
                tree.expanded.insert(prefix)
                if tree.children[prefix] == nil {
                    await loadChildren(path: prefix)
                }
            }
            tree.selected = targetPath
            tree.rebuildFlat()
            updateBreadcrumb()

            if connection?.isDataBrowsable(path: targetPath) == true {
                await loadTableData(path: targetPath, offset: 0)
            } else if targetPath.count >= 3 {
                await loadNodeDetails(path: targetPath)
            }
        }
    }

    // MARK: - Helpers

    func updateBreadcrumb() {
        var result = ""
        if let idx = activeConnectionIdx, let conn = savedConnections[safe: idx] {
            result += conn.name
            result += " | "
            result += conn.backend.displayName
        }
        if let selected = tree.selected {
            for segment in selected {
                result += " : "
                result += segment
            }
        }
        breadcrumb = result
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
