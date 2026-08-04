import AppKit
import SwiftUI
import UsageBarCore

@MainActor
enum PreviewRender {
    static func run(outputDirectory: String) async {
        let live = UsageStore()
        live.refresh()
        while live.lastRefreshed == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }

        let empty = UsageStore(defaults: scratchDefaults("empty"))
        empty.apply([
            ProviderStatus(kind: .claude, outcome: .unavailable("`claude` was not found. Install it, or make sure it is on your login shell's PATH.")),
            ProviderStatus(kind: .codex, outcome: .unavailable("`codex` was not found. Install it, or make sure it is on your login shell's PATH.")),
        ])

        let warm = UsageStore(defaults: scratchDefaults("warm"))
        warm.apply([
            ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: "max", windows: [
                UsageWindow(id: "a", windowMinutes: 300, usedPercent: 72, resetsAt: Date().addingTimeInterval(3600 * 2 + 600)),
                UsageWindow(id: "b", windowMinutes: 10080, usedPercent: 91, resetsAt: Date().addingTimeInterval(86400 * 3)),
                UsageWindow(id: "b2", windowMinutes: 10080, modelName: "Fable", usedPercent: 37, resetsAt: Date().addingTimeInterval(86400 * 3)),
            ]))),
            ProviderStatus(kind: .codex, outcome: .report(ProviderReport(plan: "pro", windows: [
                UsageWindow(id: "c", windowMinutes: 300, usedPercent: 12, resetsAt: Date().addingTimeInterval(1800)),
                UsageWindow(id: "d", windowMinutes: 10080, usedPercent: 44, resetsAt: Date().addingTimeInterval(86400 * 5)),
            ]))),
        ])

        for (name, store) in [("live", live), ("warm", warm), ("empty", empty)] {
            for dark in [false, true] {
                snapshot(
                    PopoverView(store: store),
                    dark: dark,
                    to: "\(outputDirectory)/popover-\(name)-\(dark ? "dark" : "light").png"
                )
            }
        }
        for status in live.statuses {
            print("LIVE \(status.kind.rawValue): \(status.report.map { "\($0.windows.map(\.usedPercent))" } ?? status.unavailableReason ?? "?") stale=\(status.stale?.reason ?? "-")")
        }
        fflush(stdout)

        let shapes: [(String, MenuBarReadout)] = [
            ("single", .single(17)),
            ("both", .windows([
                MenuBarReadout.Entry(id: "a", initial: "h", usedPercent: 11),
                MenuBarReadout.Entry(id: "b", initial: "w", usedPercent: 24),
            ])),
            ("one window", .windows([MenuBarReadout.Entry(id: "a", initial: "m", usedPercent: 24)])),
            ("exhausted", .windows([
                MenuBarReadout.Entry(id: "a", initial: "h", usedPercent: 100),
                MenuBarReadout.Entry(id: "b", initial: "w", usedPercent: 63),
            ])),
            ("empty", .empty),
        ]
        writeMenuBarSheet(shapes, to: "\(outputDirectory)/label.png")
        NSApplication.shared.terminate(nil)
    }

    /// Draws the status item images at 3x so they can be read. Goes through the bitmap
    /// rep because compositing a template `NSImage` directly loses its content.
    private static func writeMenuBarSheet(_ shapes: [(String, MenuBarReadout)], to path: String) {
        let scale: CGFloat = 3
        let gap: CGFloat = 24
        let images = shapes.map { ($0.0, MenuBarImage.image(for: $0.1)) }
        let width = images.reduce(gap) { $0 + $1.1.size.width * scale + gap }
        let height = MenuBarImage.height * scale + 60

        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        var x = gap
        for (name, image) in images {
            let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            // Template images are alpha masks, so they must be tinted to be visible.
            let tinted = NSImage(size: drawn)
            tinted.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: drawn))
            if image.isTemplate {
                NSColor.black.set()
                NSRect(origin: .zero, size: drawn).fill(using: .sourceAtop)
            }
            tinted.unlockFocus()
            tinted.draw(at: NSPoint(x: x, y: 34), from: .zero, operation: .sourceOver, fraction: 1)
            NSAttributedString(
                string: name,
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ).draw(at: NSPoint(x: x, y: 8))
            x += drawn.width + gap
        }
        sheet.unlockFocus()

        if let tiff = sheet.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Fixture stores get their own domain: sharing `.standard` wrote fake percentages
    /// into the real app's cached reading.
    private static func scratchDefaults(_ name: String) -> UserDefaults {
        let suite = "usagebar.preview.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func claudeWindows(of store: UsageStore) -> [MenuBarReadout.Entry] {
        let windows = store.available.first { $0.kind == .claude }?.report?.windows ?? []
        return windows.prefix(2).map {
            MenuBarReadout.Entry(id: $0.id, initial: $0.initial, usedPercent: $0.usedPercent)
        }
    }

    /// Draws through AppKit rather than `ImageRenderer` so that real controls (`Menu`,
    /// `Toggle`) appear instead of the renderer's unsupported-view placeholder.
    private static func snapshot(_ view: some View, dark: Bool, to path: String) {
        let hosting = NSHostingView(rootView: AnyView(view.background(Color(nsColor: .windowBackgroundColor))))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = hosting.appearance
        window.backgroundColor = dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard let content = window.contentView,
            let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }
}
