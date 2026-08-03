import SwiftUI

struct MenuBarLabel: View {
    let percent: Double?
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 4) {
            RingGauge(fraction: (percent ?? 0) / 100, isKnown: percent != nil)
                .frame(width: 13, height: 13)
            if let percent {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .opacity(percent == nil && isRefreshing ? 0.5 : 1)
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
