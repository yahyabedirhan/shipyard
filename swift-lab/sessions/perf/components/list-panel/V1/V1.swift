import LabHost
import SwiftUI

/// The list layout as it ships, at the heavy volume: its LazyVStack is the contrast to the tabs' VStack.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .heavy, layout: .list) }
