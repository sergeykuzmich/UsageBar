import AppKit
import SwiftUI
import Testing

@testable import UsageBarCore

/// The menu bar clips a status item label to the bar's thickness with no warning, so a
/// layout that overflows loses its bottom row silently. Two natural 10pt line boxes
/// come to 24.5pt against a 22pt bar, which is exactly how that shipped once.
@MainActor
@Suite("Menu bar label fit")
struct MenuBarLabelTests {
    static func height(_ readout: MenuBarReadout) -> CGFloat {
        NSHostingView(rootView: MenuBarLabel(readout: readout, isRefreshing: false)).fittingSize.height
    }

    static let twoWindows = MenuBarReadout.windows([
        MenuBarReadout.Entry(id: "five_hour", shortTitle: "5h", usedPercent: 9),
        MenuBarReadout.Entry(id: "seven_day", shortTitle: "7d", usedPercent: 17),
    ])

    @Test func bothWindowsFitsWithinTheMenuBar() {
        let height = Self.height(Self.twoWindows)
        #expect(height <= MenuBarLabel.menuBarThickness, "two rows need \(height)pt of a \(MenuBarLabel.menuBarThickness)pt bar")
    }

    @Test func aSingleNumberFitsWithinTheMenuBar() {
        #expect(Self.height(.single(17)) <= MenuBarLabel.menuBarThickness)
        #expect(Self.height(.empty) <= MenuBarLabel.menuBarThickness)
    }

    /// Companion to the fit check, not a substitute: this proves two rows of text are
    /// actually drawn. Overflow is caught by the height assertion above, because the
    /// bar clips from the centre and would leave ink in both halves either way.
    @Test func bothRowsAreDrawn() {
        let ink = Self.inkPerHalf(Self.twoWindows)

        #expect(ink.top > 0, "nothing drawn in the top half")
        #expect(ink.bottom > 0, "nothing drawn in the bottom half")
    }

    @Test func aSingleNumberDraws() {
        let ink = Self.inkPerHalf(.single(17))

        #expect(ink.top + ink.bottom > 0)
    }

    static func inkPerHalf(_ readout: MenuBarReadout) -> (top: Int, bottom: Int) {
        let strip = MenuBarLabel(readout: readout, isRefreshing: false)
            .environment(\.colorScheme, .light)
            .background(Color.white)

        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        guard let image = renderer.nsImage,
            let data = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else { return (0, 0) }

        var top = 0
        var bottom = 0
        let middle = bitmap.pixelsHigh / 2
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance =
                    0.2126 * pixel.redComponent + 0.7152 * pixel.greenComponent + 0.0722 * pixel.blueComponent
                guard luminance < 0.5 else { continue }
                if y < middle { top += 1 } else { bottom += 1 }
            }
        }
        return (top, bottom)
    }

    /// The constant the layout is built against has to match the real bar.
    @Test func theAssumedThicknessMatchesTheSystem() {
        let thickness = NSStatusBar.system.thickness
        #expect(thickness >= MenuBarLabel.menuBarThickness || thickness == 0, "system bar is \(thickness)pt")
    }
}
