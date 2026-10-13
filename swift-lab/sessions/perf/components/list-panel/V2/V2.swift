import LabHost
import SwiftUI

/// The fixed list layout (the hover highlight read below the layout), at the heavy volume: compare with V1.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .heavy, layout: .list) }
