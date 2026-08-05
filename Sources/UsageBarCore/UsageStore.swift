import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    /// How long a reading keeps standing in for a failed refresh. Matches the hour that
    /// Claude Code itself serves its cached utilization for.
    public static let staleLimit: TimeInterval = 3600
    /// Floor between fetches of the same provider. Claude Code throttles its own
    /// utilization cache to the same five minutes, and the endpoint rate-limits hard
    /// enough that relaunching the app in a loop is sufficient to trip it.
    public static let minFetchInterval: TimeInterval = 300
    public static let showsBothWindowsKey = "menuBarShowsBothWindows"
    static let cacheKey = "cachedReports"
    static let blockedUntilKey = "blockedUntil"

    public private(set) var statuses: [ProviderStatus] = []
    public private(set) var lastRefreshed: Date?
    public private(set) var isRefreshing = false

    public var menuBarSource: MenuBarSource {
        didSet { defaults.set(menuBarSource.rawValue, forKey: MenuBarSource.defaultsKey) }
    }

    public var showsBothWindows: Bool {
        didSet { defaults.set(showsBothWindows, forKey: Self.showsBothWindowsKey) }
    }

    private let defaults: UserDefaults
    private var cache: [ProviderKind: CachedReport]
    /// Providers the endpoint told to stay away, and until when. Persisted because
    /// relaunching mid-penalty is exactly how the limit got tripped during
    /// development.
    private var blockedUntil: [ProviderKind: Date]
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    struct CachedReport: Codable, Sendable, Equatable {
        let report: ProviderReport
        let fetchedAt: Date
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.menuBarSource = defaults.string(forKey: MenuBarSource.defaultsKey)
            .flatMap(MenuBarSource.init(rawValue:)) ?? .highest
        self.showsBothWindows = defaults.bool(forKey: Self.showsBothWindowsKey)
        self.cache = Self.loadCache(from: defaults)
        self.blockedUntil = Self.loadBlockedUntil(from: defaults)
        self.statuses = Self.statuses(fromCache: cache, now: Date())
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

        if showsBothWindows, menuBarSource.providerKind != nil, let report = reports.first {
            let windows = report.accountWindows.sorted { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }
            if !windows.isEmpty {
                return .windows(
                    windows.prefix(2).map {
                        MenuBarReadout.Entry(id: $0.id, initial: $0.initial, usedPercent: $0.usedPercent)
                    }
                )
            }
        }

        guard let highest = reports.compactMap(\.longestWindow).map(\.usedPercent).max() else { return .empty }
        return .single(highest)
    }

    /// Nil when the chosen provider has nothing to show, which leaves the menu bar
    /// showing an empty ring.
    public var headlinePercent: Double? {
        menuBarReadout.highestPercent
    }

    /// `force` is for the refresh button. Everything else honours `minFetchInterval`,
    /// so launches and timer ticks cannot stack up into a burst of requests.
    public func refresh(force: Bool = false, now: Date = Date()) {
        guard refreshTask == nil else { return }
        isRefreshing = true
        let skipped = fetchesToSkip(force: force, now: now)
        refreshTask = Task { [weak self] in
            async let claude = Self.probe(.claude, skipping: skipped)
            async let codex = Self.probe(.codex, skipping: skipped)
            let results = await [claude, codex].compactMap { $0 }
            guard let self else { return }
            self.refreshTask = nil
            self.apply(results)
        }
    }

    /// A provider inside a server-named penalty stays skipped even when forced: the
    /// server promised a 429 until then, so the refresh button would only burn a
    /// request into a wall and prolong the penalty.
    func fetchesToSkip(force: Bool, now: Date) -> Set<ProviderKind> {
        var skipped = Set(blockedUntil.filter { now < $0.value }.keys)
        guard !force else { return skipped }
        for (kind, cached) in cache where now.timeIntervalSince(cached.fetchedAt) < Self.minFetchInterval {
            skipped.insert(kind)
        }
        return skipped
    }

    private static func probe(_ kind: ProviderKind, skipping: Set<ProviderKind>) async -> ProviderStatus? {
        guard !skipping.contains(kind) else { return nil }
        switch kind {
        case .claude: return await ClaudeProbe.probe()
        case .codex: return await CodexProbe.probe()
        }
    }

    public func apply(_ results: [ProviderStatus], now: Date = Date()) {
        for result in results {
            if let report = result.report {
                cache[result.kind] = CachedReport(report: report, fetchedAt: now)
                blockedUntil[result.kind] = nil
            } else if let retryAfter = result.retryAfter {
                blockedUntil[result.kind] = retryAfter
            }
        }
        saveBlockedUntil()
        let probed = Dictionary(uniqueKeysWithValues: results.map { ($0.kind, $0) })
        statuses = ProviderKind.allCases.compactMap { kind -> ProviderStatus? in
            // A provider skipped for being fresh keeps whatever it is already showing.
            guard let result = probed[kind] else { return statuses.first { $0.kind == kind } }
            guard result.report == nil, let cached = cache[result.kind],
                now.timeIntervalSince(cached.fetchedAt) < Self.staleLimit
            else { return result }

            // The usage endpoint rate-limits, so one failed refresh keeps the previous
            // reading on screen rather than emptying the menu bar.
            return ProviderStatus(
                kind: result.kind,
                outcome: .report(cached.report),
                stale: ProviderStatus.Stale(
                    since: cached.fetchedAt,
                    reason: result.unavailableReason ?? "Could not refresh."
                )
            )
        }
        saveCache()
        lastRefreshed = now
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

    /// Seeds the display from disk so a relaunch shows numbers immediately instead of
    /// an empty ring while the CLIs are being probed.
    static func statuses(fromCache cache: [ProviderKind: CachedReport], now: Date) -> [ProviderStatus] {
        ProviderKind.allCases.compactMap { kind in
            guard let cached = cache[kind], now.timeIntervalSince(cached.fetchedAt) < staleLimit else { return nil }
            return ProviderStatus(
                kind: kind,
                outcome: .report(cached.report),
                stale: ProviderStatus.Stale(since: cached.fetchedAt, reason: "Not refreshed yet.")
            )
        }
    }

    private static func loadCache(from defaults: UserDefaults) -> [ProviderKind: CachedReport] {
        guard let data = defaults.data(forKey: cacheKey),
            let decoded = try? JSONDecoder().decode([String: CachedReport].self, from: data)
        else { return [:] }
        return decoded.reduce(into: [:]) { result, entry in
            guard let kind = ProviderKind(rawValue: entry.key) else { return }
            result[kind] = entry.value
        }
    }

    private static func loadBlockedUntil(from defaults: UserDefaults) -> [ProviderKind: Date] {
        guard let data = defaults.data(forKey: blockedUntilKey),
            let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        let now = Date()
        return decoded.reduce(into: [:]) { result, entry in
            guard let kind = ProviderKind(rawValue: entry.key), now < entry.value else { return }
            result[kind] = entry.value
        }
    }

    private func saveBlockedUntil() {
        let encodable = blockedUntil.reduce(into: [String: Date]()) { $0[$1.key.rawValue] = $1.value }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: Self.blockedUntilKey)
    }

    private func saveCache() {
        let encodable = cache.reduce(into: [String: CachedReport]()) { $0[$1.key.rawValue] = $1.value }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }
}
