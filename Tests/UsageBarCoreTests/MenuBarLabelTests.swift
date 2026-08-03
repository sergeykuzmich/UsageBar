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

    /// Ink touching the canvas edge means a glyph ran past the bounds and was cut.
    /// This is what a two-row layout built on line height instead of cap height does.
    /// Checked at 1x as well as 2x: a Retina machine hid an overshooting glyph that a
    /// non-Retina CI runner caught on the top pixel row.
    @Test func nothingIsCutOffAtTheEdges() {
        for readout in [Self.twoWindows, .single(17)] as [MenuBarReadout] {
            for scale in [1, 2] {
                let rows = Self.inkPerRow(readout, scale: scale)
                #expect(rows.first == 0, "ink on the top edge of \(readout) at \(scale)x")
                #expect(rows.last == 0, "ink on the bottom edge of \(readout) at \(scale)x")
            }
        }
    }

    /// Two rows have to carry comparable ink. A clipped row still leaves a sliver, so
    /// counting halves alone is not enough to prove both rows are whole.
    @Test func bothNumbersAreDrawn() {
        let one = MenuBarImage.image(for: .windows([
            MenuBarReadout.Entry(id: "a", initial: "h", usedPercent: 11)
        ]))
        let two = MenuBarImage.image(for: Self.twoWindows)

        #expect(two.size.width > one.size.width, "the second number is missing")
    }

    static func inkPerRow(_ readout: MenuBarReadout, scale: Int) -> [Int] {
        guard let bitmap = rasterize(MenuBarImage.image(for: readout), scale: scale) else { return [] }
        return (0..<bitmap.pixelsHigh).map { y in
            (0..<bitmap.pixelsWide).count { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 }
        }
    }

    /// `tiffRepresentation` rasterizes at whatever the attached display uses, so the
    /// scale has to be pinned to test both.
    static func rasterize(_ image: NSImage, scale: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width) * scale,
            pixelsHigh: Int(image.size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    @Test func aSingleNumberDraws() {
        let ink = Self.inkPerHalf(.single(17))

        #expect(ink.top + ink.bottom > 0)
    }

    @Test func windowsReadAsBareNumbersSplitByASlash() {
        #expect(MenuBarImage.text(forPercents: [11, 24]) == "11 / 24")
        #expect(MenuBarImage.text(forPercents: [11.4, 23.6]) == "11 / 24")
        #expect(MenuBarImage.text(forPercents: [24]) == "24")
        #expect(MenuBarImage.text(forPercents: [0, 100]) == "0 / 100")
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
        #expect(MenuBarImage.windows([99, 20]).isTemplate)
        #expect(MenuBarImage.windows([100, 20]).isTemplate == false)
        #expect(MenuBarImage.windows([20, 140]).isTemplate == false)
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
