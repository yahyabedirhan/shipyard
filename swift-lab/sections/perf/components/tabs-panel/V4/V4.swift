import LabHost
import SwiftUI

/// The tabs layout as the app has it (rows built lazily, the hover highlight read below the layout), at about the maintainer's volume: 11 projects, ~420 rows in All.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .maintainer, layout: .tabs) }
