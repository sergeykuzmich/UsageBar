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

public struct UsageWindow: Sendable, Equatable, Identifiable {
    public let id: String
    public let windowMinutes: Int?
    public let title: String
    /// Single letter for the menu bar: `h`, `d`, `w`, `m`.
    public let initial: String?
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, windowMinutes: Int?, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.windowMinutes = windowMinutes
        self.title = usageWindowTitle(windowMinutes: windowMinutes)
        self.initial = usageWindowInitial(windowMinutes: windowMinutes)
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct ProviderReport: Sendable, Equatable {
    public let plan: String?
    public let windows: [UsageWindow]

    public init(plan: String?, windows: [UsageWindow]) {
        self.plan = plan
        self.windows = windows
    }

    /// The window a single menu bar number should report. The short window swings hard
    /// and often, so a number that silently switched between the two would keep
    /// changing what it means.
    public var longestWindow: UsageWindow? {
        windows.max { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }
    }
}

public struct ProviderStatus: Sendable, Equatable, Identifiable {
    public enum Outcome: Sendable, Equatable {
        case report(ProviderReport)
        case unavailable(String)
    }

    public let kind: ProviderKind
    public let outcome: Outcome

    public var id: String { kind.rawValue }

    public init(kind: ProviderKind, outcome: Outcome) {
        self.kind = kind
        self.outcome = outcome
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
/// window where a paid one reports five hours.
public func usageWindowTitle(windowMinutes: Int?) -> String {
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
