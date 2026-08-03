import Foundation

/// Which provider's usage the menu bar number stands for.
public enum MenuBarSource: String, Sendable, CaseIterable, Identifiable {
    case highest
    case claude
    case codex

    public static let defaultsKey = "menuBarSource"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .highest: "Highest"
        case .claude: ProviderKind.claude.displayName
        case .codex: ProviderKind.codex.displayName
        }
    }

    public var providerKind: ProviderKind? {
        switch self {
        case .highest: nil
        case .claude: .claude
        case .codex: .codex
        }
    }
}

/// What the menu bar draws. `windows` only happens when a single provider is pinned,
/// because "5h" and "7d" mean nothing when the number could come from either CLI.
public enum MenuBarReadout: Sendable, Equatable {
    case empty
    case single(Double)
    case windows([Entry])

    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: String
        /// Single letter for the menu bar: `h`, `d`, `w`, `m`.
        public let initial: String?
        public let usedPercent: Double

        public init(id: String, initial: String?, usedPercent: Double) {
            self.id = id
            self.initial = initial
            self.usedPercent = usedPercent
        }
    }

    public var highestPercent: Double? {
        switch self {
        case .empty: nil
        case .single(let percent): percent
        case .windows(let entries): entries.map(\.usedPercent).max()
        }
    }
}
