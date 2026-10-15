import LabHost
import SwiftUI

/// The list layout as the app has it (the hover highlight read below the layout), at a heavy volume: 20 projects, ~1,500 rows.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .heavy, layout: .list) }
