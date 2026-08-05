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
            return ProviderStatus(kind: .claude, outcome: .unavailable(error.message), retryAfter: error.retryAfter)
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

    /// The endpoint used to send `retry-after: 0`, so a fixed backoff was ours to pick.
    /// Observed live: two 429s in a row, then a 200 on the third try about forty
    /// seconds later. When the header carries a real value it takes precedence.
    static let retryDelays: [TimeInterval] = [3, 15]

    /// The longest server-named wait worth sitting through inside one refresh. Waits
    /// past this (observed live: 2259 seconds) become a `retryAfter` date instead, so
    /// the store can stop probing until the penalty expires.
    static let maxInRefreshWait: TimeInterval = 30

    /// Deliberately silent about what the screen shows: this text is written at probe
    /// time but can be displayed an hour later, after the cached reading it once
    /// referred to was dropped.
    static let rateLimitedMessage = "Claude's usage endpoint is rate limiting."

    /// `Retry-After` is either delta-seconds or an RFC 1123 date. Zero or negative
    /// means the header has nothing to say; the endpoint sent `0` for a long time.
    static func retryAfterSeconds(from header: String) -> TimeInterval? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        let seconds: TimeInterval?
        if let numeric = TimeInterval(trimmed) {
            seconds = numeric
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            seconds = formatter.date(from: trimmed)?.timeIntervalSinceNow
        }
        guard let seconds, seconds > 0 else { return nil }
        return seconds
    }

    static func fetchWindows(
        token: String,
        session: URLSession,
        retryDelays: [TimeInterval] = ClaudeProbe.retryDelays
    ) async throws -> [UsageWindow] {
        var request = URLRequest(url: usageEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        for attempt in 0...retryDelays.count {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                return try ClaudeUsageParser.windows(from: data)
            case 401, 403:
                throw ClaudeProbeError(message: "Claude's saved token was rejected. Run `claude` once to refresh it.")
            case 429:
                let wait = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(retryAfterSeconds(from:))
                if let wait, wait > maxInRefreshWait {
                    throw ClaudeProbeError(
                        message: rateLimitedMessage,
                        retryAfter: Date(timeIntervalSinceNow: wait)
                    )
                }
                guard attempt < retryDelays.count else {
                    throw ClaudeProbeError(
                        message: rateLimitedMessage,
                        retryAfter: wait.map { Date(timeIntervalSinceNow: $0) }
                    )
                }
                try? await Task.sleep(for: .seconds(max(retryDelays[attempt], wait ?? 0)))
            default:
                throw ClaudeProbeError(message: "Claude usage request failed (HTTP \(status)).")
            }
        }
        throw ClaudeProbeError(message: rateLimitedMessage)
    }
}

public struct ClaudeProbeError: Error, Equatable {
    public let message: String
    /// When the endpoint said how long to stay away, the moment it may be contacted
    /// again. Requests before then are guaranteed 429s.
    public let retryAfter: Date?

    public init(message: String, retryAfter: Date? = nil) {
        self.message = message
        self.retryAfter = retryAfter
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
        let limits: [Limit]?

        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }

        /// The per-model weekly limits (like Fable's) do not get their own named
        /// field; they only appear as `weekly_scoped` entries in `limits`, which is
        /// where Claude Code's own /usage screen reads them from.
        struct Limit: Decodable {
            let kind: String?
            let scope: Scope?
            let percent: Double?
            let resets_at: ResetsAt?

            struct Scope: Decodable {
                let model: Model?
            }

            struct Model: Decodable {
                let display_name: String?
            }
        }

        /// `resets_at` is an ISO-8601 string in the named windows but epoch seconds
        /// in `limits`, and either could change shape; an unreadable timestamp must
        /// not throw away the whole reading.
        enum ResetsAt: Decodable {
            case epoch(Double)
            case iso(String)
            case unreadable

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let seconds = try? container.decode(Double.self) {
                    self = .epoch(seconds)
                } else if let string = try? container.decode(String.self) {
                    self = .iso(string)
                } else {
                    self = .unreadable
                }
            }

            var date: Date? {
                switch self {
                case .epoch(let seconds): Date(timeIntervalSince1970: seconds)
                case .iso(let string): ISO8601.date(from: string)
                case .unreadable: nil
                }
            }
        }
    }

    public static func windows(from data: Data) throws -> [UsageWindow] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ClaudeProbeError(message: "Could not read the Claude usage response.")
        }
        // Named by duration like the Codex windows, so both providers label the same
        // way and the menu bar abbreviations come from one place.
        let named = [("five_hour", 300, payload.five_hour), ("seven_day", 10080, payload.seven_day)]
            .compactMap { id, minutes, window -> UsageWindow? in
                guard let window, let utilization = window.utilization else { return nil }
                return UsageWindow(
                    id: id,
                    windowMinutes: minutes,
                    usedPercent: utilization,
                    resetsAt: window.resets_at.flatMap(ISO8601.date(from:))
                )
            }
        let modelScoped = (payload.limits ?? [])
            .compactMap { limit -> UsageWindow? in
                guard limit.kind == "weekly_scoped",
                    let modelName = limit.scope?.model?.display_name, !modelName.isEmpty,
                    let percent = limit.percent
                else { return nil }
                return UsageWindow(
                    id: "weekly_scoped_\(modelName.lowercased())",
                    windowMinutes: 10080,
                    modelName: modelName,
                    usedPercent: percent,
                    resetsAt: limit.resets_at?.date
                )
            }
        return named + modelScoped
    }
}
