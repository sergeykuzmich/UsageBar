import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ShellError: Error, LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut(String)
    case failed(command: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "`\(name)` was not found. Install it, or make sure it is on your login shell's PATH."
        case .launchFailed(let message):
            message
        case .timedOut(let name):
            "`\(name)` did not respond in time."
        case .failed(let command, let exitCode, let stderr):
            stderr.isEmpty ? "`\(command)` exited with code \(exitCode)." : stderr
        }
    }
}

/// A menu bar app launched by Finder inherits a bare PATH, so every CLI has to be
/// found explicitly.
public enum ExecutableLocator {
    private static let searchDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/opt/local/bin",
        "~/.local/bin",
        "~/.bun/bin",
        "~/.deno/bin",
        "~/.cargo/bin",
        "~/.volta/bin",
        "~/.npm-global/bin",
        "~/.yarn/bin",
        "~/Library/pnpm",
        "~/.nix-profile/bin",
        "/run/current-system/sw/bin",
    ]

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private var storage: [String: URL] = [:]
        private let lock = NSLock()

        func value(for key: String) -> URL? {
            lock.withLock { storage[key] }
        }

        func store(_ url: URL, for key: String) {
            lock.withLock { storage[key] = url }
        }
    }

    public static func locate(_ name: String) -> URL? {
        precondition(name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })

        if let cached = cache.value(for: name), FileManager.default.isExecutableFile(atPath: cached.path) {
            return cached
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in pathEntries + searchDirectories {
            let candidate = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                cache.store(candidate, for: name)
                return candidate
            }
        }

        if let url = locateViaLoginShell(name) {
            cache.store(url, for: name)
            return url
        }
        return nil
    }

    private static func locateViaLoginShell(_ name: String) -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let result = try? Shell.run(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-ilc", "command -v \(name)"],
            timeout: 8
        )
        guard let line = result?.stdout.split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces),
            !line.isEmpty,
            FileManager.default.isExecutableFile(atPath: line)
        else { return nil }
        return URL(fileURLWithPath: line)
    }
}

public enum Shell {
    /// Runs to completion and collects both streams. Blocking; call it off the main actor.
    public static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = childEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardInput = FileHandle.nullDevice
        process.standardError = err

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed("Could not start `\(executable.lastPathComponent)`: \(error.localizedDescription)")
        }

        let collector = StreamCollector()
        collector.drain(out.fileHandleForReading, into: .out)
        collector.drain(err.fileHandleForReading, into: .err)

        guard waitForExit(process, timeout: timeout) else {
            process.terminate()
            throw ShellError.timedOut(executable.lastPathComponent)
        }
        collector.finish()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: collector.string(.out),
            stderr: collector.string(.err)
        )
    }

    /// Keeps stdin open and streams stdout line by line until `isTerminal` accepts a
    /// line. `codex app-server` exits on stdin EOF, so the pipe has to stay open until
    /// the reply arrives.
    public static func runLineProtocol(
        executable: URL,
        arguments: [String],
        requestLines: [String],
        timeout: TimeInterval,
        isTerminal: @escaping @Sendable (Data) -> Bool
    ) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = childEnvironment()
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed("Could not start `\(executable.lastPathComponent)`: \(error.localizedDescription)")
        }
        defer {
            if process.isRunning { process.terminate() }
        }

        let stderrCollector = StreamCollector()
        stderrCollector.drain(errors.fileHandleForReading, into: .err)

        for line in requestLines {
            guard let data = (line + "\n").data(using: .utf8) else { continue }
            try? input.fileHandleForWriting.write(contentsOf: data)
        }

        let inbox = LineInbox(isTerminal: isTerminal)
        let handle = output.fileHandleForReading
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                inbox.close()
                handle.readabilityHandler = nil
            } else {
                inbox.append(chunk)
            }
        }

        let match = inbox.wait(timeout: timeout)
        handle.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        process.terminate()
        stderrCollector.finish()

        if let match { return match }

        let stderr = stderrCollector.string(.err).trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            throw ShellError.failed(command: executable.lastPathComponent, exitCode: process.terminationStatus, stderr: stderr)
        }
        throw ShellError.timedOut(executable.lastPathComponent)
    }

    /// `PATH` is rebuilt from the same directories the locator searches so that a CLI
    /// which shells out to its own helpers still finds them under a Finder-launched app.
    private static func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let defaults = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.volta/bin",
        ]
        var seen = Set<String>()
        environment["PATH"] = (existing + defaults).filter { seen.insert($0).inserted }.joined(separator: ":")

        // `claude auth status` reports a logged-out account when USER is missing.
        if environment["USER"] == nil { environment["USER"] = NSUserName() }
        if environment["LOGNAME"] == nil { environment["LOGNAME"] = NSUserName() }
        return environment
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        return done.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success
    }
}

private final class StreamCollector: @unchecked Sendable {
    enum Stream: Sendable {
        case out
        case err
    }

    private var buffers: [Stream: Data] = [:]
    private let lock = NSLock()
    private let group = DispatchGroup()

    func drain(_ handle: FileHandle, into stream: Stream) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = handle.readDataToEndOfFile()
            self.lock.withLock { self.buffers[stream, default: Data()].append(data) }
            self.group.leave()
        }
    }

    func finish() {
        _ = group.wait(timeout: .now() + 2)
    }

    func string(_ stream: Stream) -> String {
        lock.withLock { String(decoding: buffers[stream] ?? Data(), as: UTF8.self) }
    }
}

private final class LineInbox: @unchecked Sendable {
    private var pending = Data()
    private var match: Data?
    private var closed = false
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let isTerminal: @Sendable (Data) -> Bool

    init(isTerminal: @escaping @Sendable (Data) -> Bool) {
        self.isTerminal = isTerminal
    }

    func append(_ chunk: Data) {
        var completed: [Data] = []
        lock.withLock {
            guard match == nil, !closed else { return }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                completed.append(pending[pending.startIndex..<newline])
                pending = pending[pending.index(after: newline)...]
            }
        }
        for line in completed where isTerminal(line) {
            lock.withLock { if match == nil { match = line } }
            ready.signal()
            return
        }
    }

    func close() {
        lock.withLock { closed = true }
        ready.signal()
    }

    func wait(timeout: TimeInterval) -> Data? {
        _ = ready.wait(timeout: .now() + timeout)
        return lock.withLock { match }
    }
}
