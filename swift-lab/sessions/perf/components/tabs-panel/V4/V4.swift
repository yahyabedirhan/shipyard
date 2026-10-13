import LabHost
import SwiftUI

/// The fixed tabs layout (rows built lazily, the hover highlight read below the layout), at the maintainer's volume: compare with V1.
public let variant = LabVariant(window: LabWindow(titlebarAppearsTransparent: true)) { PerfLab(volume: .maintainer, layout: .tabs) }
