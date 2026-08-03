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

        let empty = UsageStore()
        empty.apply([
            ProviderStatus(kind: .claude, outcome: .unavailable("`claude` was not found. Install it, or make sure it is on your login shell's PATH.")),
            ProviderStatus(kind: .codex, outcome: .unavailable("`codex` was not found. Install it, or make sure it is on your login shell's PATH.")),
        ])

        let warm = UsageStore()
        warm.apply([
            ProviderStatus(kind: .claude, outcome: .report(ProviderReport(plan: "max", windows: [
                UsageWindow(id: "a", windowMinutes: 300, usedPercent: 72, resetsAt: Date().addingTimeInterval(3600 * 2 + 600)),
                UsageWindow(id: "b", windowMinutes: 10080, usedPercent: 91, resetsAt: Date().addingTimeInterval(86400 * 3)),
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
        let claude = claudeWindows(of: live)
        let shapes: [(String, MenuBarReadout)] = [
            ("single", .single(claude.map(\.usedPercent).max() ?? 0)),
            ("both", .windows(claude)),
            ("empty", .empty),
        ]
        snapshot(
            HStack(spacing: 22) {
                ForEach(shapes, id: \.0) { name, readout in
                    VStack(spacing: 4) {
                        MenuBarLabel(readout: readout, isRefreshing: false)
                            .fixedSize()
                            .padding(.horizontal, 6).frame(height: 24)
                        Text(name).font(.system(size: 9)).foregroundStyle(Palette.mutedInk)
                    }
                }
            }.padding(10),
            dark: false,
            to: "\(outputDirectory)/label.png"
        )
        NSApplication.shared.terminate(nil)
    }

    private static func claudeWindows(of store: UsageStore) -> [MenuBarReadout.Entry] {
        let windows = store.available.first { $0.kind == .claude }?.report?.windows ?? []
        return windows.prefix(2).map {
            MenuBarReadout.Entry(id: $0.id, shortTitle: $0.shortTitle, usedPercent: $0.usedPercent)
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
