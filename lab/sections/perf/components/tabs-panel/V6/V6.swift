import LabHost
import SwiftUI

/// The tabs layout as the app has it (rows built lazily, the hover highlight read below the layout), past what anyone has yet: 30 projects, ~3,400 rows in All.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .extreme, layout: .tabs) }
