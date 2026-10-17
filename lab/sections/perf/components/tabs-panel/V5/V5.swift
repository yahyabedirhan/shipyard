import LabHost
import SwiftUI

/// The tabs layout as the app has it (rows built lazily, the hover highlight read below the layout), at a heavy volume: 20 projects, ~1,500 rows in All.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .heavy, layout: .tabs) }
