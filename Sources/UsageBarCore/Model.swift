import Foundation

public enum ProviderKind: String, Sendable, CaseIterable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}

public struct UsageWindow: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let windowMinutes: Int?
    /// Set when the window counts only one model's usage, like Claude's weekly
    /// Fable limit. Model-scoped windows show in the popover but never drive the
    /// menu bar number.
    public let modelName: String?
    public let title: String
    /// Single letter for the menu bar: `h`, `d`, `w`, `m`.
    public let initial: String?
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, windowMinutes: Int?, modelName: String? = nil, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.windowMinutes = windowMinutes
        self.modelName = modelName
        self.title = usageWindowTitle(windowMinutes: windowMinutes, modelName: modelName)
        self.initial = usageWindowInitial(windowMinutes: windowMinutes)
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    // Only the duration and model are stored; the titles are derived so a cached
    // reading can never disagree with a freshly parsed one.
    private enum CodingKeys: String, CodingKey {
        case id, windowMinutes, modelName, usedPercent, resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            windowMinutes: try container.decodeIfPresent(Int.self, forKey: .windowMinutes),
            modelName: try container.decodeIfPresent(String.self, forKey: .modelName),
            usedPercent: try container.decode(Double.self, forKey: .usedPercent),
            resetsAt: try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(windowMinutes, forKey: .windowMinutes)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
    }
}

public struct ProviderReport: Sendable, Equatable, Codable {
    public let plan: String?
    public let windows: [UsageWindow]

    public init(plan: String?, windows: [UsageWindow]) {
        self.plan = plan
        self.windows = windows
    }

    /// The window a single menu bar number should report. The short window swings hard
    /// and often, so a number that silently switched between the two would keep
    /// changing what it means. Model-scoped windows are excluded: they run the same
    /// seven days as the all-models weekly, and Swift's sort is not stable, so a tie
    /// could otherwise flip the number between the two meanings across refreshes.
    public var longestWindow: UsageWindow? {
        accountWindows.max { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }
    }

    /// The windows that count every model, which are the only ones the menu bar reports.
    public var accountWindows: [UsageWindow] {
        windows.filter { $0.modelName == nil }
    }
}

public struct ProviderStatus: Sendable, Equatable, Identifiable {
    public enum Outcome: Sendable, Equatable {
        case report(ProviderReport)
        case unavailable(String)
    }

    /// Set when the numbers on screen came from an earlier refresh because this one
    /// failed. The usage endpoint rate-limits, and a blank menu bar is a worse answer
    /// than a slightly old one.
    public struct Stale: Sendable, Equatable {
        public let since: Date
        public let reason: String

        public init(since: Date, reason: String) {
            self.since = since
            self.reason = reason
        }
    }

    public let kind: ProviderKind
    public let outcome: Outcome
    public let stale: Stale?
    /// When the provider's endpoint said how long to stay away, the moment it may be
    /// contacted again. Fetching before then is guaranteed to fail.
    public let retryAfter: Date?

    public var id: String { kind.rawValue }

    public init(kind: ProviderKind, outcome: Outcome, stale: Stale? = nil, retryAfter: Date? = nil) {
        self.kind = kind
        self.outcome = outcome
        self.stale = stale
        self.retryAfter = retryAfter
    }

    public var report: ProviderReport? {
        if case .report(let report) = outcome { return report }
        return nil
    }

    public var unavailableReason: String? {
        if case .unavailable(let reason) = outcome { return reason }
        return nil
    }
}

/// Names a usage window by how long it runs, because the same field carries a
/// different window depending on the plan: a free Codex account reports a 30-day
/// window where a paid one reports five hours. A model-scoped window carries the
/// model's name so "Weekly" and "Weekly (Fable)" cannot be confused.
public func usageWindowTitle(windowMinutes: Int?, modelName: String? = nil) -> String {
    let base = usageWindowBaseTitle(windowMinutes: windowMinutes)
    guard let modelName, !modelName.isEmpty else { return base }
    return "\(base) (\(modelName))"
}

private func usageWindowBaseTitle(windowMinutes: Int?) -> String {
    guard let minutes = windowMinutes, minutes > 0 else { return "Usage" }
    switch minutes {
    case 10080: return "Weekly"
    case 1440: return "Daily"
    case 43200: return "Monthly"
    default: break
    }
    if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
    if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
    return "\(minutes)-minute"
}

/// One letter for the menu bar, picked by how long the window runs rather than by its
/// exact length, so a 5-hour and a 1-hour window both read as `h`.
public func usageWindowInitial(windowMinutes: Int?) -> String? {
    guard let minutes = windowMinutes, minutes > 0 else { return nil }
    switch minutes {
    case ..<1440: return "h"
    case ..<10080: return "d"
    case ..<43200: return "w"
    default: return "m"
    }
}


enum ISO8601 {
    /// The usage endpoint returns microsecond precision, which the fractional-seconds
    /// formatter rejects on some OS versions, so fall back to the plain form.
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }

        guard let dot = string.firstIndex(of: "."),
            let offsetStart = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        else { return nil }
        return plain.date(from: String(string[..<dot]) + String(string[offsetStart...]))
    }
}
