import Foundation

enum QueryAgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        }
    }

    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "hexagon"
        }
    }

    var executableNames: [String] {
        switch self {
        case .claude: ["claude"]
        case .codex: ["codex"]
        }
    }

    func arguments(workspaceURL: URL, outputURL: URL?) -> [String] {
        switch self {
        case .claude:
            [
                "--print",
                "--input-format", "text",
                "--output-format", "text",
                "--no-session-persistence",
                "--permission-mode", "dontAsk",
                "--tools", "",
            ]
        case .codex:
            codexArguments(workspaceURL: workspaceURL, outputURL: outputURL)
        }
    }

    private func codexArguments(workspaceURL: URL, outputURL: URL?) -> [String] {
        var args = [
            "exec",
            "--cd", workspaceURL.path,
            "--sandbox", "read-only",
            "--skip-git-repo-check",
            "--ephemeral",
            "--color", "never",
        ]
        if let outputURL {
            args.append(contentsOf: ["--output-last-message", outputURL.path])
        }
        args.append("-")
        return args
    }
}

struct QueryAgentLaunch: Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let currentDirectoryURL: URL
    let outputURL: URL?
}

struct QueryAgentRequest: Sendable {
    let instruction: String
    let currentQuery: String
    let databaseContext: String
}

struct QueryAgentResponse: Sendable {
    let query: String
}

enum QueryAgentError: LocalizedError {
    case missingPrompt
    case noConnection
    case missingAgent
    case launchUnavailable(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingPrompt:
            "Describe the query or correction first."
        case .noConnection:
            "Connect to a database before using an agent."
        case .missingAgent:
            "Choose an agent first."
        case .launchUnavailable(let message):
            message
        case .invalidResponse(let message):
            message
        }
    }
}
