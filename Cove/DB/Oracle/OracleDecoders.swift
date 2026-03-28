import Foundation
import OracleNIO
import NIOCore

extension OracleBackend {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    func decodeRowCells(_ row: OracleRow) -> [String?] {
        var result: [String?] = []
        var iter = row.makeIterator()
        while let cell = iter.next() {
            if cell.bytes == nil {
                result.append(nil)
            } else {
                result.append(decodeCell(cell))
            }
        }
        return result
    }

    // MARK: - Cell decoder

    private func decodeCell(_ cell: OracleCell) -> String {
        let dt = cell.dataType
        do {
            if dt == .boolean {
                return String(try cell.decode(Bool.self))
            }
            if dt == .binaryInteger {
                return String(try cell.decode(Int.self))
            }
            if dt == .number {
                return decodeNumber(cell)
            }
            if dt == .binaryFloat {
                return String(try cell.decode(Float.self))
            }
            if dt == .binaryDouble {
                return String(try cell.decode(Double.self))
            }
            if dt == .varchar || dt == .nVarchar || dt == .char || dt == .nChar
                || dt == .long || dt == .longNVarchar
            {
                return try cell.decode(String.self)
            }
            if dt == .clob || dt == .nCLOB {
                return try cell.decode(String.self)
            }
            if dt == .date {
                let date = try cell.decode(Date.self)
                return Self.dateFormatter.string(from: date)
            }
            if dt == .timestamp || dt == .timestampTZ || dt == .timestampLTZ {
                let date = try cell.decode(Date.self)
                return Self.timestampFormatter.string(from: date)
            }
            if dt == .intervalDS {
                let interval = try cell.decode(IntervalDS.self)
                return String(describing: interval)
            }
            if dt == .intervalYM {
                return try cell.decode(String.self)
            }
            if dt == .blob || dt == .raw || dt == .longRAW {
                let buf = try cell.decode(ByteBuffer.self)
                return "\\x" + buf.readableBytesView.map { String(format: "%02x", $0) }.joined()
            }
            if dt == .rowID || dt == .uRowID {
                let rowId = try cell.decode(RowID.self)
                return String(describing: rowId)
            }
            if dt == .json {
                return try cell.decode(String.self)
            }
            if dt == .cursor {
                return "[CURSOR]"
            }
            if dt == .vector {
                if let s = try? cell.decode(String.self) { return s }
                return "[VECTOR]"
            }
            return try cell.decode(String.self)
        } catch {
            return "[\(String(describing: dt))]"
        }
    }

    private func decodeNumber(_ cell: OracleCell) -> String {
        if let i = try? cell.decode(Int.self) { return String(i) }
        if let d = try? cell.decode(Double.self) { return String(d) }
        if let s = try? cell.decode(String.self) { return s }
        return "[NUMBER]"
    }
}
