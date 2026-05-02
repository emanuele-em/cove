import Foundation

actor QueryAgentSession {
    let kind: QueryAgentKind

    init(kind: QueryAgentKind) {
        self.kind = kind
    }

    func generate(request: QueryAgentRequest) async throws -> QueryAgentResponse {
        let workspaceURL = try Self.workspaceURL()
        let outputURL = kind == .codex ? Self.temporaryURL(prefix: "cove-codex-output", pathExtension: "txt") : nil
        defer {
            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        let launch = try QueryAgentLauncher.launch(for: kind, workspaceURL: workspaceURL, outputURL: outputURL)
        let prompt = QueryAgentPromptBuilder.prompt(for: request)

        let processResult = try await QueryAgentProcess.run(launch: launch, input: prompt)
        let response = try Self.preferredOutput(for: launch, processOutput: processResult.stdout)
        let query = QueryAgentPromptBuilder.sanitizeAgentResponse(response)
        guard !query.isEmpty else {
            throw QueryAgentError.invalidResponse("\(kind.displayName) did not return a query.")
        }

        return QueryAgentResponse(query: query)
    }

    private static func preferredOutput(for launch: QueryAgentLaunch, processOutput: String) throws -> String {
        guard let outputURL = launch.outputURL,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            return processOutput
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let fileOutput = try String(contentsOf: outputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fileOutput.isEmpty ? processOutput : fileOutput
    }

    private static func workspaceURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Cove/AgentWorkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func temporaryURL(prefix: String, pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}

private struct QueryAgentProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

private final class QueryAgentProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var terminationRequested = false

    var isTerminationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminationRequested
    }

    func setProcess(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = terminationRequested
        lock.unlock()

        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func clearProcess(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        terminationRequested = true
        let process = self.process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

private enum QueryAgentProcess {
    static func run(launch: QueryAgentLaunch, input: String) async throws -> QueryAgentProcessResult {
        let handle = QueryAgentProcessHandle()
        return try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .userInitiated) {
                try runBlocking(launch: launch, input: input, handle: handle)
            }.value
        }, onCancel: {
            handle.terminate()
        })
    }

    private static func runBlocking(
        launch: QueryAgentLaunch,
        input: String,
        handle: QueryAgentProcessHandle
    ) throws -> QueryAgentProcessResult {
        let stdoutURL = temporaryURL(prefix: "cove-agent-stdout", pathExtension: "log")
        let stderrURL = temporaryURL(prefix: "cove-agent-stderr", pathExtension: "log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let inputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments
        process.environment = launch.environment
        process.currentDirectoryURL = launch.currentDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        if handle.isTerminationRequested {
            throw CancellationError()
        }
        try process.run()
        handle.setProcess(process)
        defer {
            handle.clearProcess(process)
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try inputPipe.fileHandleForWriting.close()
        } catch {
            if handle.isTerminationRequested {
                throw CancellationError()
            }
            throw error
        }
        process.waitUntilExit()

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()
        if handle.isTerminationRequested {
            throw CancellationError()
        }

        let result = QueryAgentProcessResult(
            stdout: try String(contentsOf: stdoutURL, encoding: .utf8),
            stderr: try String(contentsOf: stderrURL, encoding: .utf8),
            terminationStatus: process.terminationStatus
        )
        guard result.terminationStatus == 0 else {
            throw QueryAgentError.invalidResponse(errorMessage(for: launch, result: result))
        }
        return result
    }

    private static func errorMessage(for launch: QueryAgentLaunch, result: QueryAgentProcessResult) -> String {
        let detail = result.stderr.nilIfBlank ?? result.stdout.nilIfBlank
        let command = ([launch.executablePath] + launch.arguments).joined(separator: " ")
        let executableName = URL(fileURLWithPath: launch.executablePath).lastPathComponent
        if let detail {
            return "\(executableName) failed with status \(result.terminationStatus): \(detail)\n\nCommand: \(command)"
        }
        return "\(executableName) failed with status \(result.terminationStatus).\n\nCommand: \(command)"
    }

    private static func temporaryURL(prefix: String, pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
