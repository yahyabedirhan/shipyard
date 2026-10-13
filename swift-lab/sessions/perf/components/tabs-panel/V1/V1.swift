import LabHost
import SwiftUI

/// The tabs layout as it ships, at about the maintainer's volume: 11 projects, ~420 rows in All.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .maintainer, layout: .tabs) }
