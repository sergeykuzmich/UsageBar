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

@Suite("Presentation")
struct PresentationTests {
    @Test(arguments: [
        (300, "5-hour"), (10080, "Weekly"), (1440, "Daily"), (43200, "Monthly"),
        (60, "1-hour"), (4320, "3-day"), (90, "90-minute"),
    ])
    func namesWindowsByDuration(minutes: Int, expected: String) {
        #expect(usageWindowTitle(windowMinutes: minutes) == expected)
    }

    @Test func fallsBackWhenTheWindowLengthIsUnknown() {
        #expect(usageWindowTitle(windowMinutes: nil) == "Usage")
        #expect(usageWindowTitle(windowMinutes: 0) == "Usage")
        #expect(usageWindowShortTitle(windowMinutes: nil) == nil)
        #expect(usageWindowShortTitle(windowMinutes: 0) == nil)
    }

    @Test(arguments: [
        (300, "5h"), (10080, "7d"), (1440, "1d"), (43200, "30d"), (60, "1h"), (90, "90m"),
    ])
    func abbreviatesWindowsForTheMenuBar(minutes: Int, expected: String) {
        #expect(usageWindowShortTitle(windowMinutes: minutes) == expected)
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
            MenuBarReadout.Entry(id: "five_hour", shortTitle: "5h", usedPercent: 90),
            MenuBarReadout.Entry(id: "seven_day", shortTitle: "7d", usedPercent: 16),
        ]))
    }

    @MainActor
    @Test func bothWindowsRendersOneRowPerWindow() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)
        store.menuBarSource = .claude
        store.showsBothWindows = true

        #expect(
            store.menuBarReadout == .windows([
                MenuBarReadout.Entry(id: "five_hour", shortTitle: "5h", usedPercent: 6),
                MenuBarReadout.Entry(id: "seven_day", shortTitle: "7d", usedPercent: 16),
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

    @MainActor
    @Test func bothWindowsFallsBackWhenTheProviderHasOnlyOne() {
        let store = UsageStore(defaults: Self.scratchDefaults(#function))
        store.apply(Self.bothProviders)
        store.menuBarSource = .codex
        store.showsBothWindows = true

        #expect(store.menuBarReadout == .single(18))
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
            MenuBarReadout.Entry(id: "five_hour", shortTitle: "5h", usedPercent: 6),
            MenuBarReadout.Entry(id: "seven_day", shortTitle: "7d", usedPercent: 16),
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
