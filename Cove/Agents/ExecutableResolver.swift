import Foundation

enum ExecutableResolver {
    static var searchPath: [String] {
        var paths: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    static func resolve(_ name: String) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        for dir in searchPath {
            let path = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static var processPath: String {
        searchPath.joined(separator: ":")
    }
}

enum QueryAgentLauncher {
    static func launch(for kind: QueryAgentKind, workspaceURL: URL, outputURL: URL? = nil) throws -> QueryAgentLaunch {
        for executableName in kind.executableNames {
            if let installed = ExecutableResolver.resolve(executableName) {
                return QueryAgentLaunch(
                    executablePath: installed,
                    arguments: kind.arguments(workspaceURL: workspaceURL, outputURL: outputURL),
                    environment: environment(workspaceURL: workspaceURL),
                    currentDirectoryURL: workspaceURL,
                    outputURL: outputURL
                )
            }
        }

        throw QueryAgentError.launchUnavailable(
            "\(kind.displayName) requires \(kind.executableNames.joined(separator: " or ")) on PATH."
        )
    }

    private static func environment(workspaceURL: URL) -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var env: [String: String] = [
            "PATH": ExecutableResolver.processPath,
            "PWD": workspaceURL.path,
            "NO_COLOR": "1",
        ]
        for key in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let value = source[key], !value.isEmpty {
                env[key] = value
            }
        }
        return env
    }
}
