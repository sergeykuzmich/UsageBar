import AppKit

/// MenuBarExtra turns a text-only label into the status item's *title string*, and a
/// stack of two `Text`s collapses into just the first one, which is why two rows never
/// appeared. Drawing the label and handing over a finished image is the only way to
/// control what the menu bar shows, and it is also what makes a red row possible.
public enum MenuBarImage {
    public static let height: CGFloat = 22
    public static let exhausted: Double = 100

    static let rowFontSize: CGFloat = 11
    static let singleFontSize: CGFloat = 12
    static let ringDiameter: CGFloat = 12
    static let ringGap: CGFloat = 4

    /// A template image is a pure alpha mask that the menu bar recolors to match
    /// itself, so the ink color only matters when we opt out of that for red. Drawing
    /// masks in black rather than `labelColor` keeps them identical in either
    /// appearance, which also makes them testable.
    static let maskInk = NSColor.black

    public static func image(for readout: MenuBarReadout) -> NSImage {
        switch readout {
        case .empty:
            ring(fraction: nil, trailing: nil, ink: maskInk, isTemplate: true)
        case .single(let percent):
            percent >= exhausted
                ? ring(fraction: 1, trailing: "100%", ink: .systemRed, isTemplate: false)
                : ring(
                    fraction: percent / 100,
                    trailing: "\(Int(percent.rounded()))%",
                    ink: maskInk,
                    isTemplate: true
                )
        case .windows(let entries):
            windows(entries.map { Row(initial: $0.initial, percent: $0.usedPercent) })
        }
    }

    struct Row {
        let initial: String?
        let percent: Double

        var isExhausted: Bool { percent >= MenuBarImage.exhausted }

        /// `h 10`, not `5h 10%`. The menu bar is the glance; dropping the unit and the
        /// percent sign buys the digits room to stay legible on two rows.
        var text: String {
            let value = "\(Int(percent.rounded()))"
            guard let initial else { return value }
            return "\(initial) \(value)"
        }

        var exhaustedText: String {
            guard let initial else { return "100%" }
            return "\(initial) 100%"
        }
    }

    static func windows(_ rows: [Row]) -> NSImage {
        guard !rows.isEmpty else { return ring(fraction: nil, trailing: nil, ink: maskInk, isTemplate: true) }

        // Once a window is spent, that is the whole story, so it replaces the readout
        // instead of tinting one row. It also keeps the image a single color: a
        // two-color image cannot be a template, and a baked `labelColor` would be the
        // wrong color the moment the menu bar's appearance differs from the app's.
        if let spent = rows.first(where: \.isExhausted) {
            return lines([spent.exhaustedText], fontSize: singleFontSize, ink: .systemRed, isTemplate: false)
        }
        return lines(rows.map(\.text), fontSize: rowFontSize, ink: maskInk, isTemplate: true)
    }

    /// Stacked by cap height rather than by line height. Two 11pt line boxes come to
    /// 26pt and would overflow a 22pt bar, but none of these glyphs descend below the
    /// baseline, so the rows can be packed to the height of the digits themselves.
    static func lines(_ texts: [String], fontSize: CGFloat, ink: NSColor, isTemplate: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let lines = texts.map {
            NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: ink])
        }
        let width = max(ceil(lines.map { $0.size().width }.max() ?? 0), 1)

        // Round digits overshoot the cap height slightly and antialias past that again,
        // so the padding is reserved first and the rows share whatever is left. Deriving
        // the gap from a fixed padding keeps the clear edge even at 1x, where a
        // computed-from-the-middle margin left ink on the top row of pixels.
        let padding: CGFloat = 2
        let rowCount = CGFloat(lines.count)
        let gap = rowCount > 1 ? (height - 2 * padding - rowCount * font.capHeight) / (rowCount - 1) : 0
        let topBaseline =
            rowCount > 1
            ? height - padding - font.capHeight
            : (height - font.capHeight) / 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        for (index, line) in lines.enumerated() {
            let baseline = topBaseline - CGFloat(index) * (font.capHeight + gap)
            line.draw(at: NSPoint(x: 0, y: baseline + font.descender))
        }
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }

    static func ring(fraction: Double?, trailing: String?, ink: NSColor, isTemplate: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: singleFontSize, weight: .medium)
        let label = trailing.map {
            NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: ink])
        }
        let labelWidth = label.map { ceil($0.size().width) } ?? 0
        let width = ringDiameter + (label == nil ? 0 : ringGap + labelWidth)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let radius = (ringDiameter - 1.6) / 2
        let center = NSPoint(x: ringDiameter / 2, y: height / 2)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 1.6
        ink.withAlphaComponent(0.35).setStroke()
        track.stroke()

        if let fraction {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * min(max(fraction, 0.02), 1),
                clockwise: true
            )
            arc.lineWidth = 1.6
            arc.lineCapStyle = .round
            ink.setStroke()
            arc.stroke()
        }

        if let label {
            let size = label.size()
            label.draw(at: NSPoint(x: ringDiameter + ringGap, y: (height - size.height) / 2))
        }
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }
}
