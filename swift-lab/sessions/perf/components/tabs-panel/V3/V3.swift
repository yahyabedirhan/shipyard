import LabHost
import SwiftUI

/// The tabs layout as it ships, past what anyone has yet: 30 projects, ~3,400 rows in All.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .extreme, layout: .tabs) }
