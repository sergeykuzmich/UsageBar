import AppKit
import SwiftUI
import Testing

@testable import UsageBarCore

/// The popover sits on a menu material that is lighter than `windowBackgroundColor`
/// in light mode and darker in dark mode, so measuring against the window background
/// is the conservative case: the real surface can only add contrast.
@MainActor
@Suite("Palette contrast")
struct PaletteTests {
    static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    static func contrast(_ color: Color, _ appearanceName: NSAppearance.Name) -> Double {
        contrast(NSColor(color), appearanceName)
    }

    static func contrast(_ color: NSColor, _ appearanceName: NSAppearance.Name) -> Double {
        var result = 0.0
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            let background = NSColor.windowBackgroundColor
            let front = luminance(of: color, over: background)
            let back = luminance(of: background, over: background)
            result = (max(front, back) + 0.05) / (min(front, back) + 0.05)
        }
        return result
    }

    private static func luminance(of color: NSColor, over background: NSColor) -> Double {
        guard let front = color.usingColorSpace(.sRGB), let back = background.usingColorSpace(.sRGB) else {
            return 0
        }
        let alpha = Double(front.alphaComponent)
        func blend(_ f: CGFloat, _ b: CGFloat) -> Double { Double(f) * alpha + Double(b) * (1 - alpha) }
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(blend(front.redComponent, back.redComponent))
            + 0.7152 * linear(blend(front.greenComponent, back.greenComponent))
            + 0.0722 * linear(blend(front.blueComponent, back.blueComponent))
    }

    @Test func everyTextColorMeetsAA() {
        let inks: [(String, Color)] = [
            ("primaryInk", Palette.primaryInk),
            ("secondaryInk", Palette.secondaryInk),
            ("mutedInk", Palette.mutedInk),
        ]
        for (name, ink) in inks {
            for (mode, appearance) in Self.appearances {
                let ratio = Self.contrast(ink, appearance)
                #expect(ratio >= 4.5, "\(name) in \(mode) is \(ratio):1, below the 4.5:1 AA floor")
            }
        }
    }

    /// Meter fills are non-text graphics, so the bar is 3:1. Every meter also carries
    /// its own percentage, which is what keeps the color from being the only signal.
    @Test func everyMeterFillMeetsNonTextContrast() {
        let fills: [(String, Color)] = [
            ("normal", Palette.meterFill(forPercent: 10)),
            ("warn", Palette.meterFill(forPercent: 70)),
            ("critical", Palette.meterFill(forPercent: 95)),
        ]
        for (name, fill) in fills {
            for (mode, appearance) in Self.appearances {
                let ratio = Self.contrast(fill, appearance)
                #expect(ratio >= 3.0, "meter \(name) in \(mode) is \(ratio):1, below the 3:1 floor")
            }
        }
    }

    /// Contrast alone is not enough: pushing an orange dark enough to pass on a light
    /// background turns it into a red, and then the two states look the same.
    @Test func warnAndCriticalStayTellableApart() {
        for (mode, appearance) in Self.appearances {
            let separation = Self.separation(Palette.meterWarn, Palette.meterCritical, appearance)
            #expect(separation >= 12, "warn and critical differ by only \(separation) in \(mode)")
        }
    }

    static func separation(_ a: Color, _ b: Color, _ appearanceName: NSAppearance.Name) -> Double {
        var result = 0.0
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            let first = oklab(NSColor(a)), second = oklab(NSColor(b))
            result = (pow(first.0 - second.0, 2) + pow(first.1 - second.1, 2) + pow(first.2 - second.2, 2))
                .squareRoot() * 100
        }
        return result
    }

    private static func oklab(_ color: NSColor) -> (Double, Double, Double) {
        guard let c = color.usingColorSpace(.sRGB) else { return (0, 0, 0) }
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(c.redComponent), g = linear(c.greenComponent), b = linear(c.blueComponent)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    @Test func thresholdsPickDistinctFills() {
        #expect(Palette.meterFill(forPercent: 59.9) == Palette.meterNormal)
        #expect(Palette.meterFill(forPercent: 60) == Palette.meterWarn)
        #expect(Palette.meterFill(forPercent: 84.9) == Palette.meterWarn)
        #expect(Palette.meterFill(forPercent: 85) == Palette.meterCritical)
        #expect(Palette.meterFill(forPercent: 100) == Palette.meterCritical)
    }

    /// Guards the reason this palette exists. If the system tiers ever become
    /// accessible on their own, this fails and the custom colors can go.
    @Test func systemLabelTiersStillFailInLightMode() {
        #expect(Self.contrast(NSColor.secondaryLabelColor, .aqua) < 4.5)
        #expect(Self.contrast(NSColor.tertiaryLabelColor, .aqua) < 4.5)
    }
}
