import SwiftUI

/// shipyard's logo as the welcome screens show it: the app icon's squircle,
/// graphite gradient and double rim, with the folded white sailboat
/// sized against the body as the icon sizes it. All from `Logo` and `Sailboat.path`.
struct LogoBadge: View {
    var side: CGFloat = 32

    var body: some View {
        ZStack {
            LogoShape.squircle.fill(LinearGradient(colors: [Self.color(Logo.top), Self.color(Logo.bottom)], startPoint: .top, endPoint: .bottom))
            LogoShape.figure.fill(Self.color(Logo.figure))
            LogoShape.folds.fill(Self.color(Logo.shade))
            ForEach(Logo.rims.indices, id: \.self) { i in
                let rim = Logo.rims[i]
                LogoShape.rim(i).stroke(
                    LinearGradient(colors: [.white.opacity(rim.topAlpha), .white.opacity(rim.bottomAlpha)], startPoint: .top, endPoint: .bottom),
                    lineWidth: rim.width * side)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static func color(_ hex: UInt32) -> Color { Color(cgColor: Logo.color(hex)) }
}

/// The logo's shapes, fitted to the frame they're given: the body, the
/// figure, the sails' shaded faces and each of `Logo.rims`. The body is
/// `squircle`, not `body`: a case named `body` shadows `View.body`, and
/// looking it up from another file crashed the compiler (Swift 6.3).
enum LogoShape: Shape {
    case squircle, figure, folds
    case rim(Int)

    func path(in rect: CGRect) -> Path {
        switch self {
        case .squircle: Path(Logo.squircle(in: rect))
        case .figure: Path(Logo.figurePath(inBody: rect, yDown: true))
        case .folds: Path(Logo.foldsPath(inBody: rect, yDown: true))
        case .rim(let i): Path(Logo.rimPath(Logo.rims[i], inBody: rect))
        }
    }
}
