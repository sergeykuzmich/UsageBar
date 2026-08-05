import Foundation
import Testing

@testable import UsageBarCore

@Suite("Codex usage responses")
struct CodexUsageParserTests {
    /// Captured verbatim from `codex app-server` 0.146.0 on a free plan, where the only
    /// bucket is a 30-day window reported through `primary`.
    static let freePlanResponse = Data(
        #"""
        {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,
        "primary":{"usedPercent":18,"windowDurationMins":43200,"resetsAt":1787930072},
        "secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":null},
        "individualLimit":null,"spendControlReached":false,"planType":"free",
        "rateLimitReachedType":null},"rateLimitResetCredits":{"availableCount":0,"credits":[]}}}
        """#.utf8
    )

    @Test func readsTheSingleWindowOfAFreePlan() throws {
        let report = try CodexUsageParser.report(fromResponse: Self.freePlanResponse)

        #expect(report.plan == "free")
        #expect(report.windows.count == 1)
        #expect(report.windows[0].title == "Monthly")
        #expect(report.windows[0].usedPercent == 18)
        #expect(report.windows[0].resetsAt == Date(timeIntervalSince1970: 1_787_930_072))
    }

    @Test func readsBothWindowsOfAPaidPlan() throws {
        let response = Data(
            #"""
            {"id":2,"result":{"rateLimits":{"limitId":"codex","planType":"pro",
            "primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1787930072},
            "secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1788930072}}}}
            """#.utf8
        )

        let report = try CodexUsageParser.report(fromResponse: response)

        #expect(report.plan == "pro")
        #expect(report.windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(report.windows.map(\.usedPercent) == [42, 7])
    }

    @Test func surfacesTheServerMessageOnAnRpcError() {
        let response = Data(#"{"id":2,"error":{"code":-32603,"message":"not logged in"}}"#.utf8)

        #expect(throws: CodexParseError(message: "not logged in")) {
            try CodexUsageParser.report(fromResponse: response)
        }
    }

    @Test func treatsAnEmptySnapshotAsNothingToShow() {
        let response = Data(#"{"id":2,"result":{"rateLimits":{"planType":"pro"}}}"#.utf8)

        #expect(throws: CodexParseError.self) {
            try CodexUsageParser.report(fromResponse: response)
        }
    }

    @Test func matchesOnlyTheRateLimitResponseLine() {
        let notification = Data(#"{"method":"remoteControl/status/changed","params":{}}"#.utf8)
        let initializeReply = Data(#"{"id":1,"result":{"codexHome":"/Users/x/.codex"}}"#.utf8)

        #expect(CodexProbe.isResponse(to: 2, line: notification) == false)
        #expect(CodexProbe.isResponse(to: 2, line: initializeReply) == false)
        #expect(CodexProbe.isResponse(to: 2, line: CodexUsageParserTests.freePlanResponse))
    }
}

@Suite("Claude usage responses")
struct ClaudeParserTests {
    @Test func readsBothLimitWindows() throws {
        let payload = Data(
            #"""
            {"five_hour":{"utilization":4.0,"resets_at":"2026-08-03T06:20:00.790494+00:00",
            "limit_dollars":null},"seven_day":{"utilization":16.0,
            "resets_at":"2026-08-09T13:00:00.790515+00:00"},"seven_day_opus":null,
            "extra_usage":{"is_enabled":false}}
            """#.utf8
        )

        let windows = try ClaudeUsageParser.windows(from: payload)

        #expect(windows.map(\.title) == ["5-hour", "Weekly"])
        #expect(windows.map(\.usedPercent) == [4, 16])
        #expect(windows[0].resetsAt != nil)
        #expect(windows[1].resetsAt != nil)
    }

    /// The per-model weekly limits only exist inside `limits[]`; there is no
    /// `seven_day_fable` field. `resets_at` is epoch seconds there, not ISO-8601.
    @Test func readsModelScopedWeeklyWindowsFromTheLimitsArray() throws {
        let payload = Data(
            #"""
            {"five_hour":{"utilization":4.0,"resets_at":"2026-08-03T06:20:00.790494+00:00"},
            "seven_day":{"utilization":16.0,"resets_at":"2026-08-09T13:00:00.790515+00:00"},
            "seven_day_opus":null,
            "limits":[
              {"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},
               "percent":31.0,"resets_at":1786021200},
              {"kind":"weekly_scoped","scope":null,"percent":16.0,"resets_at":1786021200},
              {"kind":"overage","scope":{"model":{"display_name":"Fable"}},"percent":2.0},
              {"kind":"weekly_scoped","scope":{"model":{"display_name":"Opus"}},
               "percent":null,"resets_at":null}
            ]}
            """#.utf8
        )

        let windows = try ClaudeUsageParser.windows(from: payload)

        #expect(windows.map(\.title) == ["5-hour", "Weekly", "Weekly (Fable)"])
        #expect(windows[2].id == "weekly_scoped_fable")
        #expect(windows[2].modelName == "Fable")
        #expect(windows[2].usedPercent == 31)
        #expect(windows[2].resetsAt == Date(timeIntervalSince1970: 1_786_021_200))
    }

    /// A malformed `limits` entry must cost only that entry, not the whole reading.
    @Test func toleratesUnreadableLimitEntries() throws {
        let payload = Data(
            #"""
            {"five_hour":{"utilization":9.0,"resets_at":null},"seven_day":null,
            "limits":[
              {"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},
               "percent":31.0,"resets_at":{"unexpected":"shape"}}
            ]}
            """#.utf8
        )

        let windows = try ClaudeUsageParser.windows(from: payload)

        #expect(windows.map(\.id) == ["five_hour", "weekly_scoped_fable"])
        #expect(windows[1].resetsAt == nil)
    }

    @Test func skipsWindowsTheAccountDoesNotHave() throws {
        let payload = Data(#"{"five_hour":{"utilization":9.0,"resets_at":null},"seven_day":null}"#.utf8)

        let windows = try ClaudeUsageParser.windows(from: payload)

        #expect(windows.count == 1)
        #expect(windows[0].id == "five_hour")
        #expect(windows[0].resetsAt == nil)
    }

    /// The endpoint sends microseconds; `ISO8601DateFormatter` only keeps milliseconds,
    /// so the assertion is on the second, not the exact fraction.
    @Test func parsesMicrosecondTimestamps() throws {
        let date = try #require(ISO8601.date(from: "2026-08-03T06:20:00.790494+00:00"))

        #expect(abs(date.timeIntervalSince1970 - 1_785_738_000.79) < 0.01)
    }

    @Test func parsesTimestampsWithoutFractionalSeconds() {
        #expect(ISO8601.date(from: "2026-08-03T06:20:00Z") == Date(timeIntervalSince1970: 1_785_738_000))
    }

    @Test func readsAuthStatus() throws {
        let payload = Data(
            #"""
            {"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty",
            "email":"a@b.c","subscriptionType":"max"}
            """#.utf8
        )

        let auth = try ClaudeAuthParser.parse(payload)

        #expect(auth.loggedIn)
        #expect(auth.authMethod == "claude.ai")
        #expect(auth.subscriptionType == "max")
    }

    @Test func readsAnAccessTokenFromTheKeychainBlob() throws {
        let blob = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-xyz","expiresAt":1785758056844}}"#.utf8)

        #expect(try ClaudeCredentialsParser.accessToken(from: blob) == "sk-ant-oat01-xyz")
    }

    @Test func rejectsCredentialsWithoutAToken() {
        #expect(throws: ClaudeProbeError.self) {
            try ClaudeCredentialsParser.accessToken(from: Data(#"{"claudeAiOauth":{}}"#.utf8))
        }
    }
}

/// Serves canned HTTP responses to `fetchWindows`. Static state, so the suite that
/// uses it must be `.serialized`.
final class StubURLProtocol: URLProtocol {
    struct Canned {
        let status: Int
        let headers: [String: String]
        let body: Data

        init(status: Int, headers: [String: String] = [:], body: Data = Data("{}".utf8)) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    nonisolated(unsafe) static var queue: [Canned] = []
    nonisolated(unsafe) static var requestCount = 0

    static func session(serving responses: [Canned]) -> URLSession {
        queue = responses
        requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let canned = Self.queue.isEmpty ? Canned(status: 429) : Self.queue.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: canned.status,
            httpVersion: "HTTP/2",
            headerFields: canned.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: canned.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Claude rate limiting", .serialized)
struct ClaudeRateLimitTests {
    static let usageBody = Data(
        #"{"five_hour":{"utilization":4.0,"resets_at":null},"seven_day":{"utilization":16.0,"resets_at":null}}"#.utf8
    )

    /// Observed live on 2026-08-04: `retry-after: 2259`. Retrying inside the refresh
    /// against a wait like that is guaranteed 429s, and the caller needs the date so
    /// it can stop probing until the penalty expires.
    @Test func aLongRetryAfterAbandonsRetriesAndCarriesTheDate() async throws {
        let session = StubURLProtocol.session(serving: [
            .init(status: 429, headers: ["Retry-After": "2259"])
        ])

        do {
            _ = try await ClaudeProbe.fetchWindows(token: "t", session: session, retryDelays: [0, 0])
            Issue.record("expected a rate limit error")
        } catch let error as ClaudeProbeError {
            #expect(StubURLProtocol.requestCount == 1)
            #expect(error.message == "Claude's usage endpoint is rate limiting.")
            let until = try #require(error.retryAfter)
            #expect(abs(until.timeIntervalSinceNow - 2259) < 30)
        }
    }

    /// `retry-after: 0` is what the endpoint used to send; it means the header has
    /// nothing to say and the fixed schedule stays in charge.
    @Test func aZeroRetryAfterKeepsTheFixedSchedule() async throws {
        let session = StubURLProtocol.session(serving: [
            .init(status: 429, headers: ["Retry-After": "0"]),
            .init(status: 429, headers: ["Retry-After": "0"]),
            .init(status: 429, headers: ["Retry-After": "0"]),
        ])

        do {
            _ = try await ClaudeProbe.fetchWindows(token: "t", session: session, retryDelays: [0, 0])
            Issue.record("expected a rate limit error")
        } catch let error as ClaudeProbeError {
            #expect(StubURLProtocol.requestCount == 3)
            #expect(error.retryAfter == nil)
        }
    }

    @Test func aShortRetryAfterWaitsAndThenSucceeds() async throws {
        let session = StubURLProtocol.session(serving: [
            .init(status: 429, headers: ["Retry-After": "1"]),
            .init(status: 200, body: Self.usageBody),
        ])

        let windows = try await ClaudeProbe.fetchWindows(token: "t", session: session, retryDelays: [0, 0])

        #expect(StubURLProtocol.requestCount == 2)
        #expect(windows.map(\.usedPercent) == [4, 16])
    }

    /// The message is written at probe time but can be displayed an hour later, after
    /// the cached reading it referred to was dropped. It must not describe the screen.
    @Test func theRateLimitMessageDoesNotClaimAReadingIsShown() async throws {
        let session = StubURLProtocol.session(serving: [
            .init(status: 429), .init(status: 429), .init(status: 429),
        ])

        do {
            _ = try await ClaudeProbe.fetchWindows(token: "t", session: session, retryDelays: [0, 0])
            Issue.record("expected a rate limit error")
        } catch let error as ClaudeProbeError {
            #expect(!error.message.contains("Showing the last reading"))
        }
    }

    @Test func anHttpDateRetryAfterIsUnderstood() {
        let until = Date().addingTimeInterval(1800)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        let seconds = ClaudeProbe.retryAfterSeconds(from: formatter.string(from: until))

        #expect(abs((seconds ?? 0) - 1800) < 5)
    }
}

@Suite("Presentation")
struct PresentationTests {
    @Test(arguments: [
        (300, "5-hour"), (10080, "Weekly"), (1440, "Daily"), (43200, "Monthly"),
        (60, "1-hour"), (4320, "3-day"), (90, "90-minute"),
    ])
    func namesWindowsByDuration(minutes: Int, expected: String) {
        #expect(usageWindowTitle(windowMinutes: minutes) == expected)
    }

    @Test func namesModelScopedWindowsWithTheModel() {
        #expect(usageWindowTitle(windowMinutes: 10080, modelName: "Fable") == "Weekly (Fable)")
        #expect(usageWindowTitle(windowMinutes: 10080, modelName: "") == "Weekly")
        #expect(usageWindowTitle(windowMinutes: nil, modelName: "Fable") == "Usage (Fable)")
    }

    @Test func fallsBackWhenTheWindowLengthIsUnknown() {
        #expect(usageWindowTitle(windowMinutes: nil) == "Usage")
        #expect(usageWindowTitle(windowMinutes: 0) == "Usage")
        #expect(usageWindowInitial(windowMinutes: nil) == nil)
        #expect(usageWindowInitial(windowMinutes: 0) == nil)
    }

    @Test(arguments: [
        (300, "h"), (60, "h"), (1440, "d"), (4320, "d"), (10080, "w"), (20160, "w"), (43200, "m"),
    ])
    func labelsWindowsWithOneLetterForTheMenuBar(minutes: Int, expected: String) {
        #expect(usageWindowInitial(windowMinutes: minutes) == expected)
    }

    @Test func formatsTimeUntilReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RelativeTime.untilReset(now.addingTimeInterval(20), now: now) == "resetting now")
        #expect(RelativeTime.untilReset(now.addingTimeInterval(90), now: now) == "resets in 1m")
        #expect(RelativeTime.untilReset(now.addingTimeInterval(3600 * 3 + 1200), now: now) == "resets in 3h 20m")
        #expect(RelativeTime.untilReset(now.addingTimeInterval(86400 * 6 + 3600 * 4), now: now) == "resets in 6d 4h")
        #expect(RelativeTime.untilReset(now.addingTimeInterval(86400 * 25), now: now) == "resets in 25d")
    }

    @Test func formatsTimeSinceUpdate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RelativeTime.sinceUpdate(now.addingTimeInterval(-5), now: now) == "updated just now")
        #expect(RelativeTime.sinceUpdate(now.addingTimeInterval(-120), now: now) == "updated 2m ago")
    }
}

@Suite("Store")
struct UsageStoreTests {
    /// A throwaway domain per test so one test's saved choice cannot leak into another.
    static func scratchDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "usagebar.tests.\(name)")!
        defaults.removePersistentDomain(forName: "usagebar.tests.\(name)")
        return defaults
    }

    static let bothProviders: [ProviderStatus] = [
        ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: "max", windows: [
            UsageWindow(id: "five_hour", windowMinutes: 300, usedPercent: 6, resetsAt: nil),
            UsageWindow(id: "seven_day", windowMinutes: 10080, usedPercent: 16, resetsAt: nil),
        ]))),
        ProviderStatus(kind: .codex, outcome: .report(ProviderReport(plan: "free", windows: [
            UsageWindow(id: "primary", windowMinutes: 43200, usedPercent: 18, resetsAt: nil)
        ]))),
    ]

    @MainActor
    @Test func headlineFollowsTheChosenProvider() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)

        #expect(store.menuBarSource == .highest)
        #expect(store.headlinePercent == 18)

        store.menuBarSource = .claude
        #expect(store.headlinePercent == 16)

        store.menuBarSource = .codex
        #expect(store.headlinePercent == 18)
    }

    static let spikingShortWindow: [ProviderStatus] = [
        ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: "max", windows: [
            UsageWindow(id: "five_hour", windowMinutes: 300, usedPercent: 90, resetsAt: nil),
            UsageWindow(id: "seven_day", windowMinutes: 10080, usedPercent: 16, resetsAt: nil),
        ]))),
        ProviderStatus(kind: .codex, outcome: .report(ProviderReport(plan: "free", windows: [
            UsageWindow(id: "primary", windowMinutes: 43200, usedPercent: 18, resetsAt: nil)
        ]))),
    ]

    /// A single number has to keep meaning the same thing. Reporting whichever window
    /// happened to be worst made it jump to the 5-hour whenever that spiked.
    @MainActor
    @Test func aSingleNumberReportsTheLongWindowEvenWhenTheShortOneIsWorse() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.spikingShortWindow)

        #expect(store.menuBarReadout == .single(18))

        store.menuBarSource = .claude
        #expect(store.menuBarReadout == .single(16))

        store.menuBarSource = .codex
        #expect(store.menuBarReadout == .single(18))
    }

    @MainActor
    @Test func theShortWindowIsStillReachableThroughBothWindows() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.spikingShortWindow)
        store.menuBarSource = .claude
        store.showsBothWindows = true

        #expect(store.menuBarReadout == .windows([
            MenuBarReadout.Entry(id: "five_hour", initial: "h", usedPercent: 90),
            MenuBarReadout.Entry(id: "seven_day", initial: "w", usedPercent: 16),
        ]))
    }

    static let withModelScopedWeekly: [ProviderStatus] = [
        ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: "max", windows: [
            UsageWindow(id: "five_hour", windowMinutes: 300, usedPercent: 6, resetsAt: nil),
            UsageWindow(id: "seven_day", windowMinutes: 10080, usedPercent: 16, resetsAt: nil),
            UsageWindow(id: "weekly_scoped_fable", windowMinutes: 10080, modelName: "Fable", usedPercent: 82, resetsAt: nil),
        ])))
    ]

    /// The Fable weekly runs the same seven days as the all-models weekly, so letting
    /// it into the menu bar would make the number ambiguous between the two and, on a
    /// sort tie, able to flip meanings between refreshes.
    @MainActor
    @Test func modelScopedWindowsNeverDriveTheMenuBar() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.withModelScopedWeekly)
        store.menuBarSource = .claude

        #expect(store.menuBarReadout == .single(16))

        store.showsBothWindows = true
        #expect(store.menuBarReadout == .windows([
            MenuBarReadout.Entry(id: "five_hour", initial: "h", usedPercent: 6),
            MenuBarReadout.Entry(id: "seven_day", initial: "w", usedPercent: 16),
        ]))
    }

    @MainActor
    @Test func modelScopedWindowsSurviveTheCacheRoundTrip() {
        let defaults = Self.scratchDefaults(#function)
        let first = UsageStore(defaults: defaults)
        first.apply(Self.withModelScopedWeekly)

        let relaunched = UsageStore(defaults: defaults)
        let claude = try! #require(relaunched.statuses.first { $0.kind == .claude })

        #expect(claude.report?.windows.map(\.title) == ["5-hour", "Weekly", "Weekly (Fable)"])
        #expect(claude.report?.windows[2].modelName == "Fable")
    }

    @MainActor
    @Test func bothWindowsRendersOneRowPerWindow() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)
        store.menuBarSource = .claude
        store.showsBothWindows = true

        #expect(
            store.menuBarReadout == .windows([
                MenuBarReadout.Entry(id: "five_hour", initial: "h", usedPercent: 6),
                MenuBarReadout.Entry(id: "seven_day", initial: "w", usedPercent: 16),
            ])
        )
        #expect(store.headlinePercent == 16)
    }

    /// "5h" and "7d" would be lying when the number could have come from either CLI.
    @MainActor
    @Test func bothWindowsFallsBackToOneNumberWhenNoProviderIsPinned() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)
        store.showsBothWindows = true

        #expect(store.menuBarSource == .highest)
        #expect(store.menuBarReadout == .single(18))
    }

    /// A free Codex plan has no short window, so there is nothing to put on the other
    /// side of the slash and the bare number stands alone.
    @MainActor
    @Test func bothWindowsShowsABareNumberWhenTheProviderHasOnlyOne() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)
        store.menuBarSource = .codex
        store.showsBothWindows = true

        #expect(store.menuBarReadout == .windows([
            MenuBarReadout.Entry(id: "primary", initial: "m", usedPercent: 18)
        ]))
    }

    @MainActor
    @Test func bothWindowsPutsTheShortWindowFirst() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.menuBarSource = .claude
        store.showsBothWindows = true
        store.apply([
            ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: "max", windows: [
                UsageWindow(id: "seven_day", windowMinutes: 10080, usedPercent: 24, resetsAt: nil),
                UsageWindow(id: "five_hour", windowMinutes: 300, usedPercent: 11, resetsAt: nil),
            ])))
        ])

        #expect(store.menuBarReadout == .windows([
            MenuBarReadout.Entry(id: "five_hour", initial: "h", usedPercent: 11),
            MenuBarReadout.Entry(id: "seven_day", initial: "w", usedPercent: 24),
        ]))
    }

    /// The server named a wait; fetching before it expires is a guaranteed 429 that
    /// only prolongs the penalty. That is also why the refresh button cannot force
    /// through it.
    @MainActor
    @Test func aRetryAfterPenaltyBlocksFetchesUntilItExpires() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        let now = Date()
        let until = now.addingTimeInterval(2259)
        store.apply(
            [ProviderStatus(kind: .claude, outcome: .unavailable("rate limiting"), retryAfter: until)],
            now: now
        )

        #expect(store.fetchesToSkip(force: false, now: until.addingTimeInterval(-1)).contains(.claude))
        #expect(store.fetchesToSkip(force: true, now: until.addingTimeInterval(-1)).contains(.claude))
        #expect(!store.fetchesToSkip(force: true, now: until.addingTimeInterval(1)).contains(.claude))
        #expect(!store.fetchesToSkip(force: false, now: until.addingTimeInterval(-1)).contains(.codex))
    }

    /// Relaunching during a penalty is exactly how the limit got tripped during
    /// development, so the block has to outlive the process.
    @MainActor
    @Test func aRetryAfterPenaltySurvivesARelaunch() {
        let defaults = Self.scratchDefaults(#function)
        let until = Date().addingTimeInterval(2259)
        let first = UsageStore(defaults: defaults)
        first.apply([ProviderStatus(kind: .claude, outcome: .unavailable("rate limiting"), retryAfter: until)])

        let relaunched = UsageStore(defaults: defaults)

        #expect(relaunched.fetchesToSkip(force: true, now: until.addingTimeInterval(-1)).contains(.claude))
        #expect(!relaunched.fetchesToSkip(force: true, now: until.addingTimeInterval(1)).contains(.claude))
    }

    @MainActor
    @Test func aSuccessfulReadingClearsThePenalty() {
        let defaults = Self.scratchDefaults(#function)
        let store = UsageStore(defaults: defaults)
        let until = Date().addingTimeInterval(2259)
        store.apply([ProviderStatus(kind: .claude, outcome: .unavailable("rate limiting"), retryAfter: until)])

        store.apply([Self.bothProviders[0]])

        #expect(!store.fetchesToSkip(force: true, now: until.addingTimeInterval(-1)).contains(.claude))
        #expect(!UsageStore(defaults: defaults).fetchesToSkip(force: true, now: until.addingTimeInterval(-1)).contains(.claude))
    }

    /// The usage endpoint rate-limits. Emptying the menu bar on a transient failure is
    /// how a working account came to show a blank ring with no explanation anywhere.
    @MainActor
    @Test func aFailedRefreshKeepsTheLastReading() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        let start = Date()
        store.apply(Self.bothProviders, now: start)

        store.apply(
            [
                ProviderStatus(kind: .claude, outcome: .unavailable("rate limited")),
                Self.bothProviders[1],
            ],
            now: start.addingTimeInterval(300)
        )

        let claude = try! #require(store.statuses.first { $0.kind == .claude })
        #expect(claude.report?.windows.map(\.usedPercent) == [6, 16])
        #expect(claude.stale?.reason == "rate limited")
        #expect(claude.stale?.since == start)
        #expect(store.available.count == 2)
    }

    @MainActor
    @Test func aReadingStopsStandingInAfterAnHour() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        let start = Date()
        store.apply(Self.bothProviders, now: start)

        store.apply(
            [ProviderStatus(kind: .claude, outcome: .unavailable("rate limited"))],
            now: start.addingTimeInterval(UsageStore.staleLimit + 1)
        )

        let claude = try! #require(store.statuses.first { $0.kind == .claude })
        #expect(claude.report == nil)
        #expect(claude.unavailableReason == "rate limited")
    }

    /// Skipping a provider that was fetched moments ago is what keeps launches and
    /// timer ticks from stacking into a burst the endpoint rejects.
    @MainActor
    @Test func aProviderFetchedMomentsAgoKeepsItsReadingWhenSkipped() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        let start = Date()
        store.apply(Self.bothProviders, now: start)

        store.apply([], now: start.addingTimeInterval(60))

        #expect(store.available.count == 2)
        #expect(store.statuses.allSatisfy { $0.stale == nil })
    }

    @MainActor
    @Test func aRelaunchStartsFromTheCachedReading() {
        let defaults = Self.scratchDefaults(#function)
        let first = UsageStore(defaults: defaults)
        first.apply(Self.bothProviders)

        let relaunched = UsageStore(defaults: defaults)

        #expect(relaunched.available.count == 2)
        #expect(relaunched.statuses.allSatisfy { $0.stale != nil })
        #expect(relaunched.menuBarReadout == .single(18))
    }

    @MainActor
    @Test func bothWindowsSurvivesARestart() {
        let defaults = Self.scratchDefaults(#function)
        let first = UsageStore(defaults: defaults)
        first.menuBarSource = .claude
        first.showsBothWindows = true

        let relaunched = UsageStore(defaults: defaults)
        relaunched.apply(Self.bothProviders)

        #expect(relaunched.showsBothWindows)
        #expect(relaunched.menuBarReadout == .windows([
            MenuBarReadout.Entry(id: "five_hour", initial: "h", usedPercent: 6),
            MenuBarReadout.Entry(id: "seven_day", initial: "w", usedPercent: 16),
        ]))
    }

    @MainActor
    @Test func defaultsToASingleNumber() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)

        #expect(store.showsBothWindows == false)
        #expect(store.menuBarReadout == .single(18))
    }

    @MainActor
    @Test func readoutIsEmptyWhenNothingAnswered() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply([
            ProviderStatus(kind: .claude, outcome: .unavailable("not installed")),
            ProviderStatus(kind: .codex, outcome: .unavailable("not installed")),
        ])

        #expect(store.menuBarReadout == .empty)
    }

    @MainActor
    @Test func headlineIsEmptyWhenTheChosenProviderDidNotAnswer() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.menuBarSource = .codex
        store.apply([
            Self.bothProviders[0],
            ProviderStatus(kind: .codex, outcome: .unavailable("`codex` was not found.")),
        ])

        #expect(store.headlinePercent == nil)
    }

    @MainActor
    @Test func theChoiceSurvivesARestart() {
        let defaults = Self.scratchDefaults(#function)
        let first = UsageStore(defaults: defaults)
        first.menuBarSource = .claude

        let relaunched = UsageStore(defaults: defaults)
        relaunched.apply(Self.bothProviders)

        #expect(relaunched.menuBarSource == .claude)
        #expect(relaunched.headlinePercent == 16)
    }

    @MainActor
    @Test func fallsBackToHighestWhenTheStoredChoiceIsUnreadable() {
        let defaults = Self.scratchDefaults(#function)
        defaults.set("gemini", forKey: MenuBarSource.defaultsKey)

        #expect(UsageStore(defaults: defaults).menuBarSource == .highest)
    }

    @MainActor
    @Test func headlineTracksTheWorstWindowAcrossProviders() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply([
            ProviderStatus(
                kind: .claude,
                outcome: .report(
                    ProviderReport(
                        plan: "max",
                        windows: [
                            UsageWindow(id: "five_hour", windowMinutes: 300, usedPercent: 4, resetsAt: nil),
                            UsageWindow(id: "seven_day", windowMinutes: 10080, usedPercent: 16, resetsAt: nil),
                        ]
                    )
                )
            ),
            ProviderStatus(kind: .codex, outcome: .unavailable("`codex` was not found.")),
        ])

        #expect(store.headlinePercent == 16)
        #expect(store.available.map(\.kind) == [.claude])
        #expect(store.unavailable.map(\.kind) == [.codex])
    }

    @MainActor
    @Test func headlineIsAbsentWhenNothingCouldBeProbed() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply([
            ProviderStatus(kind: .claude, outcome: .unavailable("not installed")),
            ProviderStatus(kind: .codex, outcome: .unavailable("not installed")),
        ])

        #expect(store.headlinePercent == nil)
        #expect(store.available.isEmpty)
    }
}
