import SwiftUI
import UsageBarCore

struct MenuBarLabel: View {
    let readout: MenuBarReadout
    let isRefreshing: Bool

    var body: some View {
        content
            .opacity(readout == .empty && isRefreshing ? 0.5 : 1)
    }

    @ViewBuilder
    private var content: some View {
        switch readout {
        case .empty:
            RingGauge(fraction: 0, isKnown: false).frame(width: 13, height: 13)
        case .single(let percent):
            HStack(spacing: 4) {
                RingGauge(fraction: percent / 100).frame(width: 13, height: 13)
                Text(percentText(percent))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        case .windows(let entries):
            // Two 10pt rows fit the 24pt menu bar in the width one 12pt row would take,
            // so showing both windows costs no menu bar space.
            VStack(alignment: .leading, spacing: -1.5) {
                ForEach(entries) { entry in
                    Text(rowText(entry))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
            }
        }
    }

    private func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    private func rowText(_ entry: MenuBarReadout.Entry) -> String {
        guard let shortTitle = entry.shortTitle else { return percentText(entry.usedPercent) }
        return "\(shortTitle) \(percentText(entry.usedPercent))"
    }
}

struct RingGauge: View {
    let fraction: Double
    var isKnown = true

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.25), lineWidth: 1.6)
            if isKnown {
                Circle()
                    .inset(by: 0.8)
                    .trim(from: 0, to: min(max(fraction, 0.01), 1))
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
