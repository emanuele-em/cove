import Foundation

final class ElasticsearchBackend: DatabaseBackend, @unchecked Sendable {
    let name = "Elasticsearch"
    private let baseURL: URL
    private let session: URLSession
    private let authHeader: String?

    // Uppercased: the syntax highlighter normalises words to uppercase before matching
    let syntaxKeywords: Set<String> = [
        "QUERY", "MATCH", "MATCH_ALL", "MATCH_PHRASE", "MULTI_MATCH",
        "BOOL", "MUST", "MUST_NOT", "SHOULD", "FILTER",
        "TERM", "TERMS", "RANGE", "EXISTS", "PREFIX", "WILDCARD", "REGEXP", "FUZZY",
        "NESTED", "HAS_CHILD", "HAS_PARENT",
        "AGGS", "AGGREGATIONS", "AVG", "SUM", "MIN", "MAX", "CARDINALITY",
        "VALUE_COUNT", "STATS", "EXTENDED_STATS", "PERCENTILES",
        "HISTOGRAM", "DATE_HISTOGRAM",
        "TOP_HITS", "SIGNIFICANT_TERMS",
        "SORT", "FROM", "SIZE", "TRACK_TOTAL_HITS",
        "HIGHLIGHT", "FIELDS", "PRE_TAGS", "POST_TAGS",
        "SCRIPT", "PAINLESS", "STORED_FIELDS", "DOCVALUE_FIELDS",
        "PIT", "SEARCH_AFTER", "COLLAPSE",
        "GTE", "GT", "LTE", "LT",
        "BOOST", "MINIMUM_SHOULD_MATCH", "ANALYZER",
        "TRUE", "FALSE", "NULL",
        "GET", "POST", "PUT", "DELETE", "HEAD", "PATCH",
    ]

    private init(baseURL: URL, session: URLSession, authHeader: String?) {
        self.baseURL = baseURL
        self.session = session
        self.authHeader = authHeader
    }

    static func connect(config: ConnectionConfig) async throws -> ElasticsearchBackend {
        let host = config.host.isEmpty ? "localhost" : config.host
        let port = config.port.isEmpty ? "9200" : config.port

        let scheme: String
        let authority: String
        if host.contains("://") {
            // User provided full scheme
            scheme = ""
            authority = host
        } else {
            scheme = "http://"
            authority = host
        }

        let urlString = "\(scheme)\(authority):\(port)"
        guard let url = URL(string: urlString) else {
            throw DbError.connection("invalid URL: \(urlString)")
        }

        var auth: String?
        if !config.user.isEmpty {
            let credentials = "\(config.user):\(config.password)"
            if let data = credentials.data(using: .utf8) {
                auth = "Basic \(data.base64EncodedString())"
            }
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: sessionConfig)

        let backend = ElasticsearchBackend(baseURL: url, session: session, authHeader: auth)

        // Verify connectivity
        let info = try await backend.request(method: "GET", path: "/") as? [String: Any]
        guard info?["cluster_name"] != nil else {
            throw DbError.connection("not an Elasticsearch cluster (missing cluster_name)")
        }

        return backend
    }

    // MARK: - HTTP helper

    func request(method: String, path: String, body: Any? = nil) async throws -> Any {
        let urlString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        guard let url = URL(string: urlString) else {
            throw DbError.query("invalid URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        // URLSession silently drops body on GET; ES accepts POST for all search endpoints
        req.httpMethod = (method == "GET" && body != nil) ? "POST" : method

        if let authHeader {
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw DbError.connection("non-HTTP response")
        }

        // Empty response (e.g. DELETE)
        if data.isEmpty {
            if http.statusCode >= 200 && http.statusCode < 300 {
                return ["acknowledged": true]
            }
            throw DbError.query("HTTP \(http.statusCode)")
        }

        let parsed = try JSONSerialization.jsonObject(with: data)

        // Check for ES error envelope
        if let dict = parsed as? [String: Any],
           let errorObj = dict["error"] {
            let reason: String
            if let errorDict = errorObj as? [String: Any] {
                reason = errorDict["reason"] as? String
                    ?? errorDict["type"] as? String
                    ?? "unknown error"
            } else if let errorStr = errorObj as? String {
                reason = errorStr
            } else {
                reason = "unknown error"
            }
            throw DbError.query(reason)
        }

        if http.statusCode >= 400 {
            throw DbError.query("HTTP \(http.statusCode)")
        }

        return parsed
    }

    /// Typed GET returning a dictionary
    func getJSON(path: String) async throws -> [String: Any] {
        guard let result = try await request(method: "GET", path: path) as? [String: Any] else {
            throw DbError.query("unexpected response format")
        }
        return result
    }
}
