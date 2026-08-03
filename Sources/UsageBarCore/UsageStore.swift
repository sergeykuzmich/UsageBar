import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public private(set) var statuses: [ProviderStatus] = []
    public private(set) var lastRefreshed: Date?
    public private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    public init() {}

    public var available: [ProviderStatus] {
        statuses.filter { $0.report != nil }
    }

    public var unavailable: [ProviderStatus] {
        statuses.filter { $0.report == nil }
    }

    /// The worst window across every provider that answered, which is the number worth
    /// carrying in the menu bar.
    public var headlinePercent: Double? {
        available.flatMap { $0.report?.windows ?? [] }.map(\.usedPercent).max()
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
