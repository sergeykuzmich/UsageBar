import SwiftUI
import UsageBarCore

struct PopoverView: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    body(now: context.date)
                }
            }
            Divider().padding(.vertical, 10)
            FooterView(store: store)
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private func body(now: Date) -> some View {
        let available = store.available
        let unavailable = store.unavailable
        if available.isEmpty {
            EmptyStateView(statuses: unavailable, isRefreshing: store.isRefreshing)
        } else {
            ForEach(Array(available.enumerated()), id: \.element.id) { index, status in
                if index > 0 {
                    Divider().padding(.vertical, 10)
                }
                ProviderSection(status: status, now: now)
            }
            // A provider that failed while the other one worked used to be invisible
            // here, which left no way to find out why the menu bar had gone blank.
            ForEach(unavailable) { status in
                Divider().padding(.vertical, 10)
                UnavailableRow(status: status)
            }
        }
    }
}

private struct ProviderSection: View {
    let status: ProviderStatus
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.kind.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let plan = status.report?.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.mutedInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Palette.badgeFill, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            ForEach(status.report?.windows ?? []) { window in
                WindowRow(window: window, now: now)
            }
            if let stale = status.stale {
                Text("\(RelativeTime.sinceUpdate(stale.since, now: now)) · \(stale.reason)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UnavailableRow: View {
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status.kind.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Text(status.unavailableReason ?? "Unavailable.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 4)
                if let resetsAt = window.resetsAt {
                    Text(RelativeTime.untilReset(resetsAt, now: now))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.mutedInk)
                }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
            Meter(percent: window.usedPercent)
        }
    }
}

private struct Meter: View {
    let percent: Double

    private var clamped: Double { min(max(percent / 100, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.meterTrack)
                Capsule()
                    .fill(Palette.meterFill(forPercent: percent))
                    .frame(width: max(clamped * geometry.size.width, clamped > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
    }
}

private struct EmptyStateView: View {
    let statuses: [ProviderStatus]
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isRefreshing && statuses.isEmpty ? "Checking…" : "No usage to show")
                .font(.system(size: 15, weight: .semibold))
            ForEach(statuses) { status in
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.kind.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                    Text(status.unavailableReason ?? "Unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct FooterView: View {
    @Bindable var store: UsageStore
    let updater = Updater.shared
    @State private var opensAtLogin = LoginItem.isEnabled

    /// Reflects back what the service actually reports, so a rejected registration
    /// leaves the toggle off instead of lying.
    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { opensAtLogin },
            set: { requested in
                LoginItem.setEnabled(requested)
                opensAtLogin = LoginItem.isEnabled
            }
        )
    }

    private func providerBinding(_ provider: ProviderKind) -> Binding<Bool> {
        Binding(
            get: { store.enabledProviders.contains(provider) },
            set: { store.setProvider(provider, enabled: $0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(store.lastRefreshed.map { RelativeTime.sinceUpdate($0) } ?? "not checked yet")
                .font(.system(size: 12))
                .foregroundStyle(Palette.mutedInk)
            Spacer()
            Button {
                store.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Refresh")

            Menu {
                if let release = updater.available {
                    Button(updater.isInstalling ? "Updating…" : "Update to \(release.tag)") {
                        updater.install()
                    }
                    .disabled(updater.isInstalling)
                    Divider()
                }
                Picker("Show in Menu Bar", selection: $store.menuBarSource) {
                    ForEach(MenuBarSource.allCases.filter { source in
                        source.providerKind.map(store.enabledProviders.contains) ?? true
                    }) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Section("Providers") {
                    ForEach(ProviderKind.allCases) { provider in
                        Toggle(provider.displayName, isOn: providerBinding(provider))
                            .disabled(store.enabledProviders == [provider])
                    }
                }
                Divider()
                Toggle("Show Both Windows", isOn: $store.showsBothWindows)
                    .disabled(store.menuBarSource == .highest)
                Toggle("Open at Login", isOn: loginItemBinding)
                Divider()
                Button("Quit UsageBar") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
        }
    }
}
