import LabHost
import SwiftUI

/// The fixed tabs layout (rows built lazily, the hover highlight read below the layout), at the extreme volume: compare with V3.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .extreme, layout: .tabs) }
