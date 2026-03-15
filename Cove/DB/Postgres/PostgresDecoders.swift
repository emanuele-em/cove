import Foundation
import PostgresNIO

extension PostgresBackend {
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

    func decodeRowCells(_ row: PostgresRow) -> [String?] {
        row.map { cell in
            if cell.bytes == nil { return nil }
            return decodeCell(cell)
        }
    }

    // MARK: - Cell decoder

    private func decodeCell(_ cell: PostgresCell) -> String {
        do {
            switch cell.dataType {
            case .bool:
                return String(try cell.decode(Bool.self))

            case .int2:
                return String(try cell.decode(Int16.self))
            case .int4, .oid:
                return String(try cell.decode(Int32.self))
            case .int8:
                return String(try cell.decode(Int64.self))

            case .float4:
                return String(try cell.decode(Float.self))
            case .float8:
                return String(try cell.decode(Double.self))

            case .numeric:
                return decodeNumeric(cell) ?? "[numeric]"

            case .uuid:
                return try cell.decode(UUID.self).uuidString

            case .date:
                if let date = try? cell.decode(Date.self) {
                    return Self.dateFormatter.string(from: date)
                }
                return "[date]"
            case .timestamp, .timestamptz:
                if let date = try? cell.decode(Date.self) {
                    return Self.timestampFormatter.string(from: date)
                }
                return "[timestamp]"
            case .time:
                return decodeTime(cell) ?? "[time]"
            case .timetz:
                return decodeTimeTz(cell) ?? "[timetz]"
            case .interval:
                return decodeInterval(cell) ?? "[interval]"

            case .jsonb:
                return decodeJsonb(cell) ?? "[jsonb]"

            case .bytea:
                return decodeBytea(cell)

            case .money:
                return decodeMoney(cell) ?? "[money]"

            case .inet, .cidr:
                return decodeInet(cell) ?? "[inet]"
            case .macaddr:
                return decodeMacaddr(cell) ?? "[macaddr]"

            default:
                return try cell.decode(String.self)
            }
        } catch {
            return "[\(cell.dataType)]"
        }
    }

    // MARK: - Binary type decoders

    private func decodeNumeric(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes else { return nil }
        guard let ndigits = buf.readInteger(as: UInt16.self),
              let weight = buf.readInteger(as: Int16.self),
              let sign = buf.readInteger(as: UInt16.self),
              let dscale = buf.readInteger(as: UInt16.self) else { return nil }

        if sign == 0xC000 { return "NaN" }
        if ndigits == 0 {
            return dscale > 0 ? "0." + String(repeating: "0", count: Int(dscale)) : "0"
        }

        var groups: [UInt16] = []
        for _ in 0..<ndigits {
            guard let d = buf.readInteger(as: UInt16.self) else { return nil }
            groups.append(d)
        }

        let prefix = sign == 0x4000 ? "-" : ""
        let intGroups = Int(weight) + 1

        var intStr = ""
        if intGroups > 0 {
            for i in 0..<intGroups {
                let d = i < groups.count ? groups[i] : 0
                intStr += i == 0 ? "\(d)" : String(format: "%04d", d)
            }
        } else {
            intStr = "0"
        }

        if dscale == 0 { return prefix + intStr }

        var fracStr = ""
        if weight < -1 {
            fracStr += String(repeating: "0", count: (-Int(weight) - 1) * 4)
        }
        let fracStart = max(intGroups, 0)
        for i in fracStart..<groups.count {
            fracStr += String(format: "%04d", groups[i])
        }
        if fracStr.count > Int(dscale) {
            fracStr = String(fracStr.prefix(Int(dscale)))
        } else {
            fracStr += String(repeating: "0", count: Int(dscale) - fracStr.count)
        }

        return prefix + intStr + "." + fracStr
    }

    private func decodeTime(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes,
              let us = buf.readInteger(as: Int64.self) else { return nil }
        return formatMicroseconds(us)
    }

    private func decodeTimeTz(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes,
              let us = buf.readInteger(as: Int64.self),
              let tzOffset = buf.readInteger(as: Int32.self) else { return nil }
        let time = formatMicroseconds(us)
        let offsetSec = -Int(tzOffset)
        let sign = offsetSec >= 0 ? "+" : "-"
        let abs = abs(offsetSec)
        return "\(time)\(sign)\(String(format: "%02d:%02d", abs / 3600, abs % 3600 / 60))"
    }

    private func decodeInterval(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes,
              let us = buf.readInteger(as: Int64.self),
              let days = buf.readInteger(as: Int32.self),
              let months = buf.readInteger(as: Int32.self) else { return nil }

        var parts: [String] = []
        let years = months / 12
        let mons = months % 12
        if years != 0 { parts.append("\(years) year\(abs(years) == 1 ? "" : "s")") }
        if mons != 0 { parts.append("\(mons) mon\(abs(mons) == 1 ? "" : "s")") }
        if days != 0 { parts.append("\(days) day\(abs(days) == 1 ? "" : "s")") }
        if us != 0 || parts.isEmpty {
            let sign = us < 0 ? "-" : ""
            parts.append(sign + formatMicroseconds(Swift.abs(us)))
        }
        return parts.joined(separator: " ")
    }

    private func formatMicroseconds(_ us: Int64) -> String {
        let totalSec = us / 1_000_000
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        let frac = us % 1_000_000
        let base = String(format: "%02d:%02d:%02d", h, m, s)
        if frac == 0 { return base }
        let fracStr = String(format: "%06d", frac)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return base + "." + fracStr
    }

    private func decodeJsonb(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes, buf.readableBytes > 1 else { return nil }
        buf.moveReaderIndex(forwardBy: 1)
        return buf.readString(length: buf.readableBytes)
    }

    private func decodeBytea(_ cell: PostgresCell) -> String {
        guard let buf = cell.bytes else { return "" }
        return "\\x" + buf.readableBytesView.map { String(format: "%02x", $0) }.joined()
    }

    private func decodeMoney(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes,
              let cents = buf.readInteger(as: Int64.self) else { return nil }
        let sign = cents < 0 ? "-" : ""
        let abs = Swift.abs(cents)
        return "\(sign)\(abs / 100).\(String(format: "%02d", abs % 100))"
    }

    private func decodeInet(_ cell: PostgresCell) -> String? {
        guard var buf = cell.bytes,
              let family = buf.readInteger(as: UInt8.self),
              let mask = buf.readInteger(as: UInt8.self),
              let isCidr = buf.readInteger(as: UInt8.self),
              let addrLen = buf.readInteger(as: UInt8.self) else { return nil }

        if family == 2, addrLen == 4 {
            guard let a = buf.readInteger(as: UInt8.self),
                  let b = buf.readInteger(as: UInt8.self),
                  let c = buf.readInteger(as: UInt8.self),
                  let d = buf.readInteger(as: UInt8.self) else { return nil }
            let addr = "\(a).\(b).\(c).\(d)"
            return (isCidr == 1 || mask < 32) ? "\(addr)/\(mask)" : addr
        }
        if family == 3, addrLen == 16 {
            var groups: [String] = []
            for _ in 0..<8 {
                guard let g = buf.readInteger(as: UInt16.self) else { return nil }
                groups.append(String(format: "%x", g))
            }
            let addr = groups.joined(separator: ":")
            return (isCidr == 1 || mask < 128) ? "\(addr)/\(mask)" : addr
        }
        return nil
    }

    private func decodeMacaddr(_ cell: PostgresCell) -> String? {
        guard let buf = cell.bytes, buf.readableBytes == 6 else { return nil }
        return buf.readableBytesView.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
