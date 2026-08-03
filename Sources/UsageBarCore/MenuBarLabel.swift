import SwiftUI

public struct MenuBarLabel: View {
    public static let rowFontSize: CGFloat = 10
    public static let rowHeight: CGFloat = 10
    public static let rowSpacing: CGFloat = 1
    /// What `NSStatusBar.system.thickness` reports, and the height the label is clipped to.
    public static let menuBarThickness: CGFloat = 22

    public let readout: MenuBarReadout
    public let isRefreshing: Bool

    public init(readout: MenuBarReadout, isRefreshing: Bool) {
        self.readout = readout
        self.isRefreshing = isRefreshing
    }

    public var body: some View {
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
            // The menu bar is 22pt tall and two natural 10pt line boxes come to 24.5pt,
            // which silently clips the second row. None of these glyphs descend below
            // the baseline, so the boxes can be clamped to the type size and fit in 21pt.
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(entries) { entry in
                    Text(rowText(entry))
                        .font(.system(size: Self.rowFontSize, weight: .medium).monospacedDigit())
                        .frame(height: Self.rowHeight)
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

public struct RingGauge: View {
    public let fraction: Double
    public var isKnown = true

    public init(fraction: Double, isKnown: Bool = true) {
        self.fraction = fraction
        self.isKnown = isKnown
    }

    public var body: some View {
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
