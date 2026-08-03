import Foundation

public enum ClaudeProbe {
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    public static func probe(session: URLSession = .shared) async -> ProviderStatus {
        do {
            let auth = try await offMainActor { try readAuth() }
            guard auth.loggedIn else {
                return unavailable("Not signed in. Run `claude` to log in.")
            }
            guard auth.authMethod == "claude.ai" else {
                return unavailable("Signed in with \(auth.authMethod ?? "an API key"), which has no subscription limits.")
            }

            let token = try await offMainActor { try readAccessToken() }
            let windows = try await fetchWindows(token: token, session: session)
            guard !windows.isEmpty else {
                return unavailable("No usage limits reported for this account.")
            }
            return ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: auth.subscriptionType, windows: windows)))
        } catch let error as ShellError {
            return unavailable(error.errorDescription ?? "\(error)")
        } catch let error as ClaudeProbeError {
            return unavailable(error.message)
        } catch {
            return unavailable(error.localizedDescription)
        }
    }

    private static func unavailable(_ reason: String) -> ProviderStatus {
        ProviderStatus(kind: .claude, outcome: .unavailable(reason))
    }

    private static func readAuth() throws -> ClaudeAuth {
        guard let executable = ExecutableLocator.locate(ProviderKind.claude.executableName) else {
            throw ShellError.executableNotFound(ProviderKind.claude.executableName)
        }
        let result = try Shell.run(executable: executable, arguments: ["auth", "status", "--json"], timeout: 30)
        guard result.exitCode == 0 else {
            throw ShellError.failed(
                command: "claude auth status",
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return try ClaudeAuthParser.parse(Data(result.stdout.utf8))
    }

    /// Reads the token through `/usr/bin/security` rather than the Security framework:
    /// the keychain grant is bound to the caller's code signature, and an ad-hoc signed
    /// app gets a new identity on every build, which would re-prompt after each update.
    static func readAccessToken() throws -> String {
        let security = URL(fileURLWithPath: "/usr/bin/security")
        let result = try Shell.run(
            executable: security,
            arguments: ["find-generic-password", "-s", keychainService, "-w"],
            timeout: 20
        )
        if result.exitCode == 0, let token = try? ClaudeCredentialsParser.accessToken(from: Data(result.stdout.utf8)) {
            return token
        }

        let fallback = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: fallback),
            let token = try? ClaudeCredentialsParser.accessToken(from: data) {
            return token
        }

        throw ClaudeProbeError(message: "Could not read Claude's credentials from the keychain. Approve the access prompt, or run `claude` to sign in again.")
    }

    private static func fetchWindows(token: String, session: URLSession) async throws -> [UsageWindow] {
        var request = URLRequest(url: usageEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            return try ClaudeUsageParser.windows(from: data)
        case 401, 403:
            throw ClaudeProbeError(message: "Claude's saved token was rejected. Run `claude` once to refresh it.")
        default:
            throw ClaudeProbeError(message: "Claude usage request failed (HTTP \(status)).")
        }
    }
}

public struct ClaudeProbeError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct ClaudeAuth: Sendable, Equatable {
    public let loggedIn: Bool
    public let authMethod: String?
    public let subscriptionType: String?
}

public enum ClaudeAuthParser {
    private struct Payload: Decodable {
        let loggedIn: Bool?
        let authMethod: String?
        let subscriptionType: String?
    }

    public static func parse(_ data: Data) throws -> ClaudeAuth {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ClaudeProbeError(message: "Could not read `claude auth status` output.")
        }
        return ClaudeAuth(
            loggedIn: payload.loggedIn ?? false,
            authMethod: payload.authMethod,
            subscriptionType: payload.subscriptionType
        )
    }
}

public enum ClaudeCredentialsParser {
    private struct Payload: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
        }
        let claudeAiOauth: OAuth?
    }

    public static func accessToken(from data: Data) throws -> String {
        guard let token = (try? JSONDecoder().decode(Payload.self, from: data))?.claudeAiOauth?.accessToken,
            !token.isEmpty
        else {
            throw ClaudeProbeError(message: "Claude's stored credentials did not contain an access token.")
        }
        return token
    }
}

public enum ClaudeUsageParser {
    private struct Payload: Decodable {
        let five_hour: Window?
        let seven_day: Window?

        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
    }

    public static func windows(from data: Data) throws -> [UsageWindow] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ClaudeProbeError(message: "Could not read the Claude usage response.")
        }
        return [("five_hour", "5-hour", payload.five_hour), ("seven_day", "Weekly", payload.seven_day)]
            .compactMap { id, title, window in
                guard let window, let utilization = window.utilization else { return nil }
                return UsageWindow(
                    id: id,
                    title: title,
                    usedPercent: utilization,
                    resetsAt: window.resets_at.flatMap(ISO8601.date(from:))
                )
            }
    }
}
