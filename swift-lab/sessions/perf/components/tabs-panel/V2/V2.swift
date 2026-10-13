import LabHost
import SwiftUI

/// The tabs layout as it ships, at a heavy volume: 20 projects, ~1,500 rows in All.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .heavy, layout: .tabs) }
