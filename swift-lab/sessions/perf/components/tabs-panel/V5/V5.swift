import LabHost
import SwiftUI

/// The fixed tabs layout (rows built lazily, the hover highlight read below the layout), at the heavy volume: compare with V2.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .heavy, layout: .tabs) }
