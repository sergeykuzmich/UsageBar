import AppKit
import Testing

@testable import UsageBarCore

/// MenuBarExtra collapses a text-only label into the status item's title string, and a
/// stack of two `Text`s came out as only the first row. These tests work on the drawn
/// image, which is what the menu bar actually receives.
@MainActor
@Suite("Menu bar image")
struct MenuBarImageTests {
    static let twoWindows = MenuBarReadout.windows([
        MenuBarReadout.Entry(id: "five_hour", initial: "h", usedPercent: 10),
        MenuBarReadout.Entry(id: "seven_day", initial: "w", usedPercent: 17),
    ])

    @Test func everyShapeFitsTheMenuBar() {
        let thickness = NSStatusBar.system.thickness
        for readout in [Self.twoWindows, .single(17), .empty] as [MenuBarReadout] {
            let height = MenuBarImage.image(for: readout).size.height
            #expect(height <= MenuBarImage.height)
            #expect(thickness == 0 || height <= thickness, "\(height)pt drawn into a \(thickness)pt bar")
        }
    }

    /// The bug this file exists for: the second row silently went missing.
    @Test func bothRowsAreDrawn() {
        let ink = Self.inkPerHalf(Self.twoWindows)

        #expect(ink.top > 0, "top row missing")
        #expect(ink.bottom > 0, "bottom row missing")
    }

    /// Ink touching the canvas edge means a glyph ran past the bounds and was cut.
    /// This is what a two-row layout built on line height instead of cap height does.
    @Test func nothingIsCutOffAtTheEdges() {
        for readout in [Self.twoWindows, .single(17)] as [MenuBarReadout] {
            let rows = Self.inkPerRow(readout)
            #expect(rows.first == 0, "ink on the top edge of \(readout)")
            #expect(rows.last == 0, "ink on the bottom edge of \(readout)")
        }
    }

    /// Two rows have to carry comparable ink. A clipped row still leaves a sliver, so
    /// counting halves alone is not enough to prove both rows are whole.
    @Test func neitherRowIsShortchanged() {
        let ink = Self.inkPerHalf(Self.twoWindows)
        let ratio = Double(min(ink.top, ink.bottom)) / Double(max(ink.top, ink.bottom))

        #expect(ratio > 0.6, "rows are lopsided: \(ink)")
    }

    static func inkPerRow(_ readout: MenuBarReadout) -> [Int] {
        let image = MenuBarImage.image(for: readout)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return [] }
        return (0..<bitmap.pixelsHigh).map { y in
            (0..<bitmap.pixelsWide).count { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 }
        }
    }

    @Test func aSingleNumberDraws() {
        let ink = Self.inkPerHalf(.single(17))

        #expect(ink.top + ink.bottom > 0)
    }

    @Test func rowsDropTheUnitAndThePercentSign() {
        #expect(MenuBarImage.Row(initial: "h", percent: 10).text == "h 10")
        #expect(MenuBarImage.Row(initial: "w", percent: 17.4).text == "w 17")
        #expect(MenuBarImage.Row(initial: "m", percent: 99.6).text == "m 100")
        #expect(MenuBarImage.Row(initial: nil, percent: 8).text == "8")
    }

    /// A red row has to keep its color, and the menu bar recolors template images.
    @Test func anExhaustedWindowOptsOutOfTemplateRendering() {
        let normal = MenuBarImage.image(for: Self.twoWindows)
        let exhausted = MenuBarImage.image(for: .windows([
            MenuBarReadout.Entry(id: "a", initial: "h", usedPercent: 100),
            MenuBarReadout.Entry(id: "b", initial: "w", usedPercent: 17),
        ]))

        #expect(normal.isTemplate, "a normal label must follow the menu bar's own color")
        #expect(exhausted.isTemplate == false, "a red row would be recolored away as a template")
    }

    @Test func exhaustionStartsAtAHundred() {
        #expect(MenuBarImage.Row(initial: "h", percent: 99.4).isExhausted == false)
        #expect(MenuBarImage.Row(initial: "h", percent: 100).isExhausted)
        #expect(MenuBarImage.Row(initial: "h", percent: 140).isExhausted)
    }

    @Test func widthTracksTheWidestRow() {
        let narrow = MenuBarImage.image(for: .windows([
            MenuBarReadout.Entry(id: "a", initial: "h", usedPercent: 1),
            MenuBarReadout.Entry(id: "b", initial: "w", usedPercent: 2),
        ]))
        let wide = MenuBarImage.image(for: .windows([
            MenuBarReadout.Entry(id: "a", initial: "h", usedPercent: 100),
            MenuBarReadout.Entry(id: "b", initial: "w", usedPercent: 2),
        ]))

        #expect(wide.size.width > narrow.size.width)
    }

    static func inkPerHalf(_ readout: MenuBarReadout) -> (top: Int, bottom: Int) {
        let image = MenuBarImage.image(for: readout)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return (0, 0)
        }

        var top = 0
        var bottom = 0
        let middle = bitmap.pixelsHigh / 2
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.3 else { continue }
                if y < middle { top += 1 } else { bottom += 1 }
            }
        }
        return (top, bottom)
    }
}
