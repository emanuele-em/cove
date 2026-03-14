import Foundation
import MySQLNIO

extension MySQLBackend {

    func decodeRow(_ row: MySQLRow) -> [String?] {
        row.columnDefinitions.map { colDef in
            guard let data = row.column(colDef.name) else { return nil }
            if data.buffer == nil { return nil }
            return decodeData(data)
        }
    }

    func columnInfoFromRow(_ row: MySQLRow) -> [ColumnInfo] {
        row.columnDefinitions.map { colDef in
            ColumnInfo(
                name: colDef.name,
                typeName: colDef.columnType.name,
                isPrimaryKey: false
            )
        }
    }

    // MARK: - Data decoder

    private func decodeData(_ data: MySQLData) -> String {
        let t = data.type

        if t == .tiny || t == .short || t == .long || t == .longlong || t == .int24 {
            if data.isUnsigned {
                return data.uint.map { String($0) } ?? "[int]"
            }
            return data.int.map { String($0) } ?? "[int]"
        }

        if t == .float {
            return data.float.map { String($0) } ?? "[float]"
        }

        if t == .double {
            return data.double.map { String($0) } ?? "[double]"
        }

        if t == .newdecimal || t == .decimal {
            return data.string ?? "[decimal]"
        }

        if t == .varchar || t == .varString || t == .string || t == .enum || t == .set {
            return data.string ?? ""
        }

        if t == .blob || t == .tinyBlob || t == .mediumBlob || t == .longBlob {
            if let str = data.string { return str }
            guard let buf = data.buffer else { return "" }
            return "\\x" + buf.readableBytesView.map { String(format: "%02x", $0) }.joined()
        }

        if t == .json {
            return data.string ?? "[json]"
        }

        if t == .date || t == .newdate {
            if let time = data.time {
                return String(format: "%04d-%02d-%02d",
                              time.year ?? 0, time.month ?? 0, time.day ?? 0)
            }
            return data.string ?? "[date]"
        }

        if t == .datetime || t == .timestamp {
            if let time = data.time {
                return String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                              time.year ?? 0, time.month ?? 0, time.day ?? 0,
                              time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
            }
            return data.string ?? "[datetime]"
        }

        if t == .time {
            if let time = data.time {
                return String(format: "%02d:%02d:%02d",
                              time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
            }
            return data.string ?? "[time]"
        }

        if t == .year {
            return data.string ?? "[year]"
        }

        if t == .bit {
            return data.bool.map { String($0) } ?? "[bit]"
        }

        if t == .geometry {
            return "[geometry]"
        }

        return data.string ?? "[\(data.type)]"
    }
}
