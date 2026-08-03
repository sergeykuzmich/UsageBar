import AppKit
import SwiftUI

/// Every color here clears WCAG AA against the popover background in both
/// appearances, which the system label tiers do not: `.secondary` measures 3.82:1
/// and `.tertiary` measures 1.86:1 in light mode. `PaletteTests` holds the numbers,
/// so change a value there and the test tells you what it costs.
public enum Palette {
    public static let primaryInk = Color.primary
    public static let secondaryInk = Color.primary.opacity(0.78)
    public static let mutedInk = Color.primary.opacity(0.66)

    public static let meterTrack = Color.primary.opacity(0.10)
    public static let badgeFill = Color.primary.opacity(0.08)

    public static let meterNormal = Color.primary.opacity(0.72)
    public static let meterWarn = Color(nsColor: warn)
    public static let meterCritical = Color(nsColor: critical)

    /// System orange is 1.86:1 on a light background, so light mode gets a burnt
    /// orange instead. Dark mode keeps the native color, which already measures 6.24:1.
    /// The light pair is also chosen for distance from `critical`: darkening an orange
    /// far enough to pass contrast walks it straight into red.
    static let warn = NSColor(name: "usagebar.meter.warn") { appearance in
        appearance.isDark ? .systemOrange : NSColor(srgbRed: 0.800, green: 0.333, blue: 0.0, alpha: 1)
    }

    static let critical = NSColor(name: "usagebar.meter.critical") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.0, green: 0.420, blue: 0.369, alpha: 1)
            : NSColor(srgbRed: 0.600, green: 0.106, blue: 0.106, alpha: 1)
    }

    public static func meterFill(forPercent percent: Double) -> Color {
        switch percent {
        case ..<60: meterNormal
        case ..<85: meterWarn
        default: meterCritical
        }
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
