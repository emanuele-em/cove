import Foundation
import CassandraClient

extension ScyllaBackend {
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

    // MARK: - Type-aware decoder (used when CQL type is known)

    func decodeColumn(_ col: CassandraClient.Column?, cqlType: String) -> String? {
        guard let col else { return nil }
        let isNull = col.withUnsafeBuffer { $0 == nil }
        if isNull { return nil }
        return decodeTyped(col, cqlType: cqlType)
    }

    // MARK: - Untyped fallback (used for ad-hoc queries)

    func decodeColumnUntyped(_ col: CassandraClient.Column?) -> String? {
        guard let col else { return nil }
        let isNull = col.withUnsafeBuffer { $0 == nil }
        if isNull { return nil }

        // Try binary-only types before string to avoid garbled output
        if let u = col.uuid { return u.uuidString }
        if let b = col.bool { return String(b) }
        if let s = col.string { return s }
        if let i = col.int32 { return String(i) }
        if let i = col.int64 { return String(i) }
        if let i = col.int16 { return String(i) }
        if let i = col.int8 { return String(i) }
        if let u = col.uint32 { return String(u) }
        if let d = col.double { return String(d) }
        if let f = col.float32 { return String(f) }
        if let bytes = col.bytes {
            return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
        }
        return "[?]"
    }

    // MARK: - Typed dispatch

    private func decodeTyped(_ col: CassandraClient.Column, cqlType: String) -> String {
        let t = cqlType.trimmingCharacters(in: .whitespaces).lowercased()

        switch t {
        case "text", "varchar", "ascii":
            return col.string ?? "[\(t)]"

        case "int":
            return col.int32.map(String.init) ?? "[int]"
        case "bigint", "counter":
            return col.int64.map(String.init) ?? "[bigint]"
        case "smallint":
            return col.int16.map(String.init) ?? "[smallint]"
        case "tinyint":
            return col.int8.map(String.init) ?? "[tinyint]"

        case "float":
            return col.float32.map { String($0) } ?? "[float]"
        case "double":
            return col.double.map { String($0) } ?? "[double]"

        case "boolean":
            return col.bool.map(String.init) ?? "[boolean]"

        case "uuid":
            return col.uuid?.uuidString ?? "[uuid]"
        case "timeuuid":
            return col.uuid?.uuidString ?? "[timeuuid]"

        case "timestamp":
            if let ms = col.int64 {
                let date = Date(timeIntervalSince1970: Double(ms) / 1000)
                return Self.timestampFormatter.string(from: date)
            }
            return "[timestamp]"

        case "date":
            if let days = col.uint32 {
                // CQL date: unsigned 32-bit days since epoch center (2^31)
                let epoch = Int64(days) - 2_147_483_648
                let date = Date(timeIntervalSince1970: Double(epoch) * 86400)
                return Self.dateFormatter.string(from: date)
            }
            return "[date]"

        case "time":
            if let nanos = col.int64 {
                return formatNanoseconds(nanos)
            }
            return "[time]"

        case "blob":
            if let bytes = col.bytes {
                return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
            }
            return "[blob]"

        case "inet":
            return decodeInet(col) ?? "[inet]"
        case "varint":
            return decodeVarint(col) ?? "[varint]"
        case "decimal":
            return decodeDecimal(col) ?? "[decimal]"
        case "duration":
            return decodeDuration(col) ?? "[duration]"

        default:
            // Collection types: map<…>, list<…>, set<…>, frozen<…>, tuple<…>
            if t.hasPrefix("frozen<") {
                let inner = String(t.dropFirst(7).dropLast(1))
                return decodeTyped(col, cqlType: inner)
            }
            if t.hasPrefix("map<") {
                return decodeMap(col) ?? "[map]"
            }
            if t.hasPrefix("list<") || t.hasPrefix("set<") {
                return decodeListOrSet(col) ?? "[collection]"
            }
            if t.hasPrefix("tuple<") {
                return decodeTuple(col) ?? "[tuple]"
            }
            // Unknown — best effort
            if let s = col.string { return s }
            if let bytes = col.bytes {
                return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
            }
            return "[\(t)]"
        }
    }

    // MARK: - Time

    private func formatNanoseconds(_ nanos: Int64) -> String {
        let totalSec = nanos / 1_000_000_000
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        let frac = nanos % 1_000_000_000
        let base = String(format: "%02d:%02d:%02d", h, m, s)
        if frac == 0 { return base }
        let fracStr = String(format: "%09d", frac)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return base + "." + fracStr
    }

    // MARK: - Inet

    private func decodeInet(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes else { return nil }
        if bytes.count == 4 {
            return bytes.map(String.init).joined(separator: ".")
        }
        if bytes.count == 16 {
            var groups: [String] = []
            for i in stride(from: 0, to: 16, by: 2) {
                let g = (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
                groups.append(String(format: "%x", g))
            }
            return groups.joined(separator: ":")
        }
        return nil
    }

    // MARK: - Varint

    private func decodeVarint(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes, !bytes.isEmpty else { return nil }
        return varintToString(bytes)
    }

    private func varintToString(_ bytes: [UInt8]) -> String {
        let isNegative = bytes[0] & 0x80 != 0

        if bytes.count <= 8 {
            var value: UInt64 = 0
            for b in bytes { value = (value << 8) | UInt64(b) }
            if isNegative {
                if bytes.count == 8 {
                    return String(Int64(bitPattern: value))
                }
                let signExtended = value | (UInt64.max << (UInt64(bytes.count) * 8))
                return String(Int64(bitPattern: signExtended))
            }
            return String(value)
        }
        return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Decimal

    private func decodeDecimal(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes, bytes.count >= 5 else { return nil }

        let scale = readBigEndianInt32(bytes, at: 0)
        let varintBytes = Array(bytes[4...])
        let unscaled = varintToString(varintBytes)

        guard scale > 0 else { return unscaled }

        let isNeg = unscaled.hasPrefix("-")
        let digits = isNeg ? String(unscaled.dropFirst()) : unscaled
        guard !digits.hasPrefix("0x") else { return unscaled }

        let s = Int(scale)
        if digits.count <= s {
            let padded = String(repeating: "0", count: s - digits.count + 1) + digits
            let intPart = String(padded.prefix(padded.count - s))
            let fracPart = String(padded.suffix(s))
            return (isNeg ? "-" : "") + intPart + "." + fracPart
        }
        let intPart = String(digits.prefix(digits.count - s))
        let fracPart = String(digits.suffix(s))
        return (isNeg ? "-" : "") + intPart + "." + fracPart
    }

    // MARK: - Duration (vint-encoded months, days, nanos)

    private func decodeDuration(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes, !bytes.isEmpty else { return nil }
        var offset = 0
        guard let months = readVint(bytes, &offset),
              let days = readVint(bytes, &offset),
              let nanos = readVint(bytes, &offset) else { return nil }

        var parts: [String] = []
        let yrs = months / 12
        let mons = months % 12
        if yrs != 0 { parts.append("\(yrs)y") }
        if mons != 0 { parts.append("\(mons)mo") }
        if days != 0 { parts.append("\(days)d") }
        if nanos != 0 || parts.isEmpty {
            let totalMs = nanos / 1_000_000
            let h = totalMs / 3_600_000
            let m = (totalMs % 3_600_000) / 60_000
            let s = (totalMs % 60_000) / 1000
            let ms = totalMs % 1000
            if h != 0 { parts.append("\(h)h") }
            if m != 0 { parts.append("\(m)m") }
            if s != 0 || ms != 0 {
                parts.append(ms == 0 ? "\(s)s" : "\(s).\(String(format: "%03d", abs(ms)))s")
            }
        }
        return parts.isEmpty ? "0s" : parts.joined(separator: "")
    }

    // Zigzag-decoded vint (CQL duration encoding)
    private func readVint(_ bytes: [UInt8], _ offset: inout Int) -> Int64? {
        guard offset < bytes.count else { return nil }
        let first = bytes[offset]
        let extraBytes = (~first).leadingZeroBitCount
        guard offset + extraBytes < bytes.count else { return nil }

        var raw: Int64
        if extraBytes == 0 {
            raw = Int64(first)
            offset += 1
        } else {
            raw = Int64(first & (0xFF >> (extraBytes + 1)))
            for i in 1...extraBytes {
                raw = (raw << 8) | Int64(bytes[offset + i])
            }
            offset += extraBytes + 1
        }
        return (raw >> 1) ^ -(raw & 1)
    }

    // MARK: - Collections

    private func decodeMap(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes, bytes.count >= 4 else { return nil }
        var off = 0
        let n = Int(readBigEndianInt32(bytes, at: off)); off += 4
        guard n >= 0, n < 100_000 else { return nil }

        var pairs: [String] = []
        for _ in 0..<n {
            guard let key = readCollectionElement(bytes, &off),
                  let val = readCollectionElement(bytes, &off) else { break }
            pairs.append("\(key): \(val)")
        }
        return "{\(pairs.joined(separator: ", "))}"
    }

    private func decodeListOrSet(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes, bytes.count >= 4 else { return nil }
        var off = 0
        let n = Int(readBigEndianInt32(bytes, at: off)); off += 4
        guard n >= 0, n < 100_000 else { return nil }

        var elems: [String] = []
        for _ in 0..<n {
            guard let elem = readCollectionElement(bytes, &off) else { break }
            elems.append(elem)
        }
        return "[\(elems.joined(separator: ", "))]"
    }

    private func decodeTuple(_ col: CassandraClient.Column) -> String? {
        guard let bytes = col.bytes, bytes.count >= 4 else { return nil }
        var off = 0
        var elems: [String] = []
        while off + 4 <= bytes.count {
            guard let elem = readCollectionElement(bytes, &off) else { break }
            elems.append(elem)
        }
        return "(\(elems.joined(separator: ", ")))"
    }

    // MARK: - Binary helpers

    private func readCollectionElement(_ bytes: [UInt8], _ offset: inout Int) -> String? {
        guard offset + 4 <= bytes.count else { return nil }
        let len = Int(readBigEndianInt32(bytes, at: offset)); offset += 4
        if len < 0 { return "null" }
        guard offset + len <= bytes.count else { return nil }
        let data = bytes[offset..<(offset + len)]
        offset += len
        return String(bytes: data, encoding: .utf8)
            ?? "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    private func readBigEndianInt32(_ bytes: [UInt8], at i: Int) -> Int32 {
        Int32(bitPattern:
            (UInt32(bytes[i]) << 24) | (UInt32(bytes[i+1]) << 16) |
            (UInt32(bytes[i+2]) << 8) | UInt32(bytes[i+3])
        )
    }
}
