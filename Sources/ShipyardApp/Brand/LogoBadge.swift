import SwiftUI

/// shipyard's logo as the welcome screens show it: the app icon's squircle,
/// olive khaki gradient and sheen, with the cream sailboat sized against the
/// body as the icon sizes it. All from `Logo` and `Sailboat.path`.
struct LogoBadge: View {
    var side: CGFloat = 32

    var body: some View {
        ZStack {
            LogoShape.body.fill(LinearGradient(colors: [Self.color(Logo.top), Self.color(Logo.bottom)], startPoint: .top, endPoint: .bottom))
            LogoShape.body.fill(LinearGradient(colors: [.white.opacity(Logo.sheen), .white.opacity(0)], startPoint: .top, endPoint: .center))
            LogoShape.figure.fill(Self.color(Logo.figure))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static func color(_ hex: UInt32) -> Color { Color(cgColor: Logo.color(hex)) }
}

/// The logo's two shapes, fitted to the frame they're given.
enum LogoShape: Shape {
    case body, figure

    func path(in rect: CGRect) -> Path {
        switch self {
        case .body: Path(Logo.squircle(in: rect))
        case .figure: Path(Logo.figurePath(inBody: rect, yDown: true))
        }
    }
}
