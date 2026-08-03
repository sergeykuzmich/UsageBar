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
        if available.isEmpty {
            EmptyStateView(statuses: store.unavailable, isRefreshing: store.isRefreshing)
        } else {
            ForEach(Array(available.enumerated()), id: \.element.id) { index, status in
                if index > 0 {
                    Divider().padding(.vertical, 10)
                }
                ProviderSection(status: status, now: now)
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
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            ForEach(status.report?.windows ?? []) { window in
                WindowRow(window: window, now: now)
            }
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
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let resetsAt = window.resetsAt {
                    Text(RelativeTime.untilReset(resetsAt, now: now))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
            Meter(fraction: window.usedPercent / 100)
        }
    }
}

private struct Meter: View {
    let fraction: Double

    private var clamped: Double { min(max(fraction, 0), 1) }

    private var fill: Color {
        switch clamped {
        case ..<0.6: .primary.opacity(0.72)
        case ..<0.85: .orange
        default: .red
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule()
                    .fill(fill)
                    .frame(width: max(clamped * geometry.size.width, clamped > 0 ? 5 : 0))
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
                        .foregroundStyle(.secondary)
                    Text(status.unavailableReason ?? "Unavailable.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct FooterView: View {
    @Bindable var store: UsageStore
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

    var body: some View {
        HStack(spacing: 8) {
            Text(store.lastRefreshed.map { RelativeTime.sinceUpdate($0) } ?? "not checked yet")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Refresh")

            Menu {
                Picker("Show in Menu Bar", selection: $store.menuBarSource) {
                    ForEach(MenuBarSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.inline)
                Divider()
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
