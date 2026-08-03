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
