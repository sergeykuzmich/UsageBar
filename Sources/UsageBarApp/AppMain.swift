import SwiftUI
import UsageBarCore

@main
struct UsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = UsageStore.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarLabel(readout: store.menuBarReadout, isRefreshing: store.isRefreshing)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let arguments = CommandLine.arguments
            if let index = arguments.firstIndex(of: "--render-preview"), index + 1 < arguments.count {
                let directory = arguments[index + 1]
                Task { await PreviewRender.run(outputDirectory: directory) }
                return
            }
            UsageStore.shared.startAutoRefresh()
        }
    }
}

extension UsageStore {
    @MainActor static let shared = UsageStore()
}
