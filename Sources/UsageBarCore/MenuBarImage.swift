import AppKit

/// MenuBarExtra turns a text-only label into the status item's *title string*, and a
/// stack of two `Text`s collapses into just the first one, which is why two rows never
/// appeared. Drawing the label and handing over a finished image is the only way to
/// control what the menu bar shows, and it is also what makes a red label possible.
public enum MenuBarImage {
    public static let height: CGFloat = 22
    public static let exhausted: Double = 100

    static let fontSize: CGFloat = 12
    static let ringDiameter: CGFloat = 12
    static let ringGap: CGFloat = 4
    static let padding: CGFloat = 2

    /// A template image is a pure alpha mask that the menu bar recolors to match
    /// itself, so ink color only matters when we opt out of that for red. Drawing masks
    /// in black rather than `labelColor` keeps them identical in either appearance,
    /// which also makes them testable.
    static let maskInk = NSColor.black

    public static func image(for readout: MenuBarReadout) -> NSImage {
        switch readout {
        case .empty:
            ring(fraction: nil, trailing: nil, ink: maskInk, isTemplate: true)
        case .single(let percent):
            ring(
                fraction: percent / 100,
                trailing: "\(rounded(percent))%",
                ink: percent >= exhausted ? .systemRed : maskInk,
                isTemplate: percent < exhausted
            )
        case .windows(let entries):
            windows(entries.map(\.usedPercent))
        }
    }

    /// `11 / 24`, shortest window first. No unit and no percent sign: the menu bar is
    /// the glance, and the numbers are the only part worth the space.
    static func text(forPercents percents: [Double]) -> String {
        percents.map(rounded).map(String.init).joined(separator: " / ")
    }

    static func windows(_ percents: [Double]) -> NSImage {
        guard !percents.isEmpty else { return ring(fraction: nil, trailing: nil, ink: maskInk, isTemplate: true) }

        // One spent window colors the whole label. A two-color image cannot be a
        // template, and a template is what lets the menu bar recolor it for its own
        // appearance, so this is all-or-nothing.
        let spent = percents.contains { $0 >= exhausted }
        return line(text(forPercents: percents), ink: spent ? .systemRed : maskInk, isTemplate: !spent)
    }

    static func line(_ text: String, ink: NSColor, isTemplate: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let line = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        let width = max(ceil(line.size().width), 1)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        line.draw(at: NSPoint(x: 0, y: baseline(for: font) + font.descender))
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }

    /// Round digits overshoot the cap height and antialias past that again, so the
    /// glyphs are centred on cap height with padding reserved rather than on the line
    /// box. A tighter margin left ink on the top pixel row of CI's renderer.
    static func baseline(for font: NSFont) -> CGFloat {
        max((height - font.capHeight) / 2, padding)
    }

    static func rounded(_ percent: Double) -> Int {
        Int(percent.rounded())
    }

    static func ring(fraction: Double?, trailing: String?, ink: NSColor, isTemplate: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
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
            label.draw(at: NSPoint(x: ringDiameter + ringGap, y: baseline(for: font) + font.descender))
        }
        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }
}
