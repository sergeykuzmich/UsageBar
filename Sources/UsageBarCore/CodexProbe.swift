import Foundation

public enum CodexProbe {
    static let requestID = 2

    static let requestLines = [
        #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"usagebar","version":"0.1.0"}}}"#,
        #"{"method":"initialized","params":{}}"#,
        #"{"id":\#(requestID),"method":"account/rateLimits/read","params":{}}"#,
    ]

    public static func probe() async -> ProviderStatus {
        let outcome: ProviderStatus.Outcome
        do {
            outcome = .report(try await offMainActor { try readReport() })
        } catch let error as ShellError {
            outcome = .unavailable(error.errorDescription ?? "\(error)")
        } catch let error as CodexParseError {
            outcome = .unavailable(error.message)
        } catch {
            outcome = .unavailable(error.localizedDescription)
        }
        return ProviderStatus(kind: .codex, outcome: outcome)
    }

    private static func readReport() throws -> ProviderReport {
        guard let executable = ExecutableLocator.locate(ProviderKind.codex.executableName) else {
            throw ShellError.executableNotFound(ProviderKind.codex.executableName)
        }
        let line = try Shell.runLineProtocol(
            executable: executable,
            arguments: ["app-server"],
            requestLines: requestLines,
            timeout: 25,
            isTerminal: { isResponse(to: requestID, line: $0) }
        )
        return try CodexUsageParser.report(fromResponse: line)
    }

    static func isResponse(to id: Int, line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return false }
        return (object["id"] as? Int) == id
    }
}

public struct CodexParseError: Error, Equatable {
    public let message: String
}

public enum CodexUsageParser {
    private struct Response: Decodable {
        struct Failure: Decodable {
            let message: String?
        }
        let result: Result?
        let error: Failure?

        struct Result: Decodable {
            let rateLimits: Snapshot?
        }

        struct Snapshot: Decodable {
            let planType: String?
            let primary: Window?
            let secondary: Window?
        }

        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int?
            let resetsAt: Double?
        }
    }

    public static func report(fromResponse data: Data) throws -> ProviderReport {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CodexParseError(message: "Could not read the Codex usage response.")
        }

        if let failure = response.error {
            throw CodexParseError(message: failure.message ?? "Codex refused the usage request.")
        }
        guard let snapshot = response.result?.rateLimits else {
            throw CodexParseError(message: "Codex returned no usage data.")
        }

        let windows = [("primary", snapshot.primary), ("secondary", snapshot.secondary)]
            .compactMap { name, window -> UsageWindow? in
                guard let window else { return nil }
                return UsageWindow(
                    id: name,
                    windowMinutes: window.windowDurationMins,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            }

        guard !windows.isEmpty else {
            throw CodexParseError(message: "No usage limits reported yet. Run `codex` once.")
        }
        return ProviderReport(plan: snapshot.planType, windows: windows)
    }
}
