import Foundation

enum DbError: Error, LocalizedError {
    case connection(String)
    case query(String)
    case invalidPath(expected: Int, got: Int)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .connection(let msg): "connection failed: \(msg)"
        case .query(let msg): "query failed: \(msg)"
        case .invalidPath(let expected, let got): "invalid path: expected \(expected) segments, got \(got)"
        case .other(let msg): msg
        }
    }
}
