import SwiftUI

public struct MenuBarLabel: View {
    public let readout: MenuBarReadout
    public let isRefreshing: Bool

    public init(readout: MenuBarReadout, isRefreshing: Bool) {
        self.readout = readout
        self.isRefreshing = isRefreshing
    }

    public var body: some View {
        Image(nsImage: MenuBarImage.image(for: readout))
            .opacity(readout == .empty && isRefreshing ? 0.5 : 1)
    }
}
