import Foundation
import RediStack
import NIOCore
import NIOPosix
import Logging

final class RedisBackend: DatabaseBackend, @unchecked Sendable {
    let name = "Redis"
    let config: ConnectionConfig
    private let lock = NSLock()
    private var pools: [Int: RedisConnectionPool] = [:]
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    let syntaxKeywords: Set<String> = [
        "GET", "SET", "DEL", "EXISTS", "EXPIRE", "TTL", "PTTL", "PERSIST",
        "KEYS", "SCAN", "TYPE", "RENAME", "RENAMENX", "UNLINK",
        "MGET", "MSET", "MSETNX", "APPEND", "INCR", "DECR", "INCRBY",
        "DECRBY", "INCRBYFLOAT", "STRLEN", "GETRANGE", "SETRANGE",
        "SETNX", "SETEX", "PSETEX", "GETSET", "GETDEL",
        "HGET", "HSET", "HDEL", "HEXISTS", "HGETALL", "HKEYS", "HVALS",
        "HLEN", "HMGET", "HMSET", "HINCRBY", "HINCRBYFLOAT", "HSCAN",
        "HSETNX",
        "LPUSH", "RPUSH", "LPOP", "RPOP", "LLEN", "LRANGE", "LINDEX",
        "LSET", "LINSERT", "LREM", "LTRIM", "RPOPLPUSH", "LPOS",
        "SADD", "SREM", "SMEMBERS", "SISMEMBER", "SCARD", "SPOP",
        "SRANDMEMBER", "SDIFF", "SINTER", "SUNION", "SSCAN",
        "ZADD", "ZREM", "ZSCORE", "ZRANK", "ZREVRANK", "ZRANGE",
        "ZRANGEBYSCORE", "ZCARD", "ZCOUNT", "ZINCRBY", "ZSCAN",
        "ZRANGEBYLEX", "ZLEXCOUNT", "ZPOPMIN", "ZPOPMAX",
        "XADD", "XLEN", "XRANGE", "XREVRANGE", "XREAD", "XDEL",
        "XTRIM", "XINFO", "XGROUP", "XREADGROUP", "XACK", "XCLAIM",
        "SELECT", "DBSIZE", "FLUSHDB", "FLUSHALL", "INFO", "CONFIG",
        "PING", "ECHO", "AUTH", "QUIT", "OBJECT", "MEMORY", "DEBUG",
        "CLIENT", "COMMAND", "MONITOR", "SUBSCRIBE", "PUBLISH",
        "MULTI", "EXEC", "DISCARD", "WATCH", "UNWATCH",
        "DUMP", "RESTORE", "MOVE", "COPY", "WAIT",
        "CLUSTER", "READONLY", "READWRITE", "SENTINEL",
    ]

    private init(config: ConnectionConfig, eventLoopGroup: MultiThreadedEventLoopGroup) {
        self.config = config
        self.eventLoopGroup = eventLoopGroup
    }

    static func connect(config: ConnectionConfig) async throws -> RedisBackend {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let backend = RedisBackend(config: config, eventLoopGroup: elg)

        let db = Int(config.database) ?? 0
        let pool = try backend.makePool(database: db)
        backend.lock.withLock { backend.pools[db] = pool }

        do {
            let pong = try await pool.ping().get()
            guard pong == "PONG" else {
                throw DbError.connection("unexpected PING response: \(pong)")
            }
        } catch let error as DbError {
            throw error
        } catch {
            throw DbError.connection(error.localizedDescription)
        }

        return backend
    }

    func poolFor(db: Int) throws -> RedisConnectionPool {
        if let existing = lock.withLock({ pools[db] }) {
            return existing
        }
        let pool = try makePool(database: db)
        lock.withLock { pools[db] = pool }
        return pool
    }

    private func makePool(database: Int) throws -> RedisConnectionPool {
        let port = Int(config.port) ?? 6379
        let address = try SocketAddress.makeAddressResolvingHost(config.host, port: port)

        let factoryConfig = RedisConnectionPool.ConnectionFactoryConfiguration(
            connectionInitialDatabase: database == 0 ? nil : database,
            connectionUsername: config.user.isEmpty ? nil : config.user,
            connectionPassword: config.password.isEmpty ? nil : config.password,
            connectionDefaultLogger: Logger(label: "cove.redis")
        )

        let poolConfig = RedisConnectionPool.Configuration(
            initialServerConnectionAddresses: [address],
            maximumConnectionCount: .maximumActiveConnections(2),
            connectionFactoryConfiguration: factoryConfig
        )

        return RedisConnectionPool(
            configuration: poolConfig,
            boundEventLoop: eventLoopGroup.next()
        )
    }

    static let typeGroups: [(name: String, redisType: String, icon: String, tint: NodeTint)] = [
        ("Strings",      "string", "textformat.abc",       NodeTint(r: 0.420, g: 0.624, b: 0.800)),
        ("Hashes",       "hash",   "number.square",        NodeTint(r: 0.878, g: 0.647, b: 0.412)),
        ("Lists",        "list",   "list.number",          NodeTint(r: 0.529, g: 0.753, b: 0.518)),
        ("Sets",         "set",    "circle.grid.3x3",      NodeTint(r: 0.694, g: 0.506, b: 0.804)),
        ("Sorted Sets",  "zset",   "chart.bar.xaxis",      NodeTint(r: 0.773, g: 0.525, b: 0.753)),
        ("Streams",      "stream", "arrow.right.circle",   NodeTint(r: 0.400, g: 0.694, b: 0.659)),
    ]

    func sendCommand(_ command: String, _ args: [String], db: Int) async throws -> RESPValue {
        let pool = try poolFor(db: db)
        let respArgs = args.map { RESPValue(from: $0) }
        return try await pool.send(command: command, with: respArgs).get()
    }

    deinit {
        for pool in pools.values {
            pool.close()
        }
        try? eventLoopGroup.syncShutdownGracefully()
    }
}
