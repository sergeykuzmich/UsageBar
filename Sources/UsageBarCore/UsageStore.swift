import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public private(set) var statuses: [ProviderStatus] = []
    public private(set) var lastRefreshed: Date?
    public private(set) var isRefreshing = false

    public static let showsBothWindowsKey = "menuBarShowsBothWindows"

    public var menuBarSource: MenuBarSource {
        didSet { defaults.set(menuBarSource.rawValue, forKey: MenuBarSource.defaultsKey) }
    }

    public var showsBothWindows: Bool {
        didSet { defaults.set(showsBothWindows, forKey: Self.showsBothWindowsKey) }
    }

    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.menuBarSource = defaults.string(forKey: MenuBarSource.defaultsKey)
            .flatMap(MenuBarSource.init(rawValue:)) ?? .highest
        self.showsBothWindows = defaults.bool(forKey: Self.showsBothWindowsKey)
    }

    public var available: [ProviderStatus] {
        statuses.filter { $0.report != nil }
    }

    public var unavailable: [ProviderStatus] {
        statuses.filter { $0.report == nil }
    }

    public var menuBarReadout: MenuBarReadout {
        let scoped = menuBarSource.providerKind.map { kind in available.filter { $0.kind == kind } } ?? available
        let reports = scoped.compactMap(\.report)

        if showsBothWindows, menuBarSource.providerKind != nil,
            let windows = reports.first?.windows, windows.count > 1 {
            return .windows(
                windows.prefix(2).map {
                    MenuBarReadout.Entry(id: $0.id, initial: $0.initial, usedPercent: $0.usedPercent)
                }
            )
        }

        guard let highest = reports.compactMap(\.longestWindow).map(\.usedPercent).max() else { return .empty }
        return .single(highest)
    }

    /// Nil when the chosen provider did not answer, which leaves the menu bar showing
    /// an empty ring.
    public var headlinePercent: Double? {
        menuBarReadout.highestPercent
    }

    public func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            async let claude = ClaudeProbe.probe()
            async let codex = CodexProbe.probe()
            let results = await [claude, codex]
            guard let self else { return }
            self.refreshTask = nil
            self.apply(results)
        }
    }

    public func apply(_ results: [ProviderStatus]) {
        statuses = results
        lastRefreshed = Date()
        isRefreshing = false
    }

    public func startAutoRefresh(every interval: Duration = .seconds(300)) {
        autoRefreshTask?.cancel()
        refresh()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
