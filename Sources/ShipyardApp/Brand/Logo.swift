import CoreGraphics

enum Logo {
    static let top: UInt32 = 0x222529
    static let bottom: UInt32 = 0x131417
    static let figure: UInt32 = 0xFFFFFF
    static let shade: UInt32 = 0xB9BEC4

    struct Rim {
        let inset: CGFloat, width: CGFloat, topAlpha: CGFloat, bottomAlpha: CGFloat
    }

    static let rims = [
        Rim(inset: 4 / 256, width: 2 / 256, topAlpha: 0.32, bottomAlpha: 0.08),
        Rim(inset: 12 / 256, width: 1.5 / 256, topAlpha: 0.14, bottomAlpha: 0.03),
    ]
    static var smallRims: [Rim] { Array(rims.prefix(1)) }

    static func rimPath(_ rim: Rim, inBody body: CGRect) -> CGPath {
        squircle(in: body.insetBy(dx: rim.inset * body.width, dy: rim.inset * body.width))
    }

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    static let iconBody: CGFloat = 824
    static let figureScale: CGFloat = 0.92
    static let smallFigureScale: CGFloat = 1.1

    static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let n: CGFloat = 5
        let a = rect.width / 2, b = rect.height / 2
        let steps = 720
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = a * copysign(pow(abs(c), 2 / n), c)
            let y = b * copysign(pow(abs(s), 2 / n), s)
            let p = CGPoint(x: rect.midX + x, y: rect.midY + y)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    nonisolated(unsafe) static let folds: CGPath = {
        let deck: CGFloat = 401
        let faces = CGMutablePath()
        faces.addLines(between: [
            CGPoint(x: 0, y: deck), CGPoint(x: 413.6, y: deck), CGPoint(x: 482, y: 734),
            CGPoint(x: 482, y: 1024), CGPoint(x: 0, y: 1024),
        ])
        faces.closeSubpath()
        faces.addLines(between: [
            CGPoint(x: 512, y: deck), CGPoint(x: 605.5, y: deck), CGPoint(x: 548, y: 808),
            CGPoint(x: 548, y: 1024), CGPoint(x: 512, y: 1024),
        ])
        faces.closeSubpath()
        return Sailboat.path.intersection(faces)
    }()

    static func figureTransform(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGAffineTransform {
        let scale = (small ? smallFigureScale : figureScale) * body.width / iconBody
        return Sailboat.transform(centredAt: CGPoint(x: body.midX, y: body.midY), scale: scale, yDown: yDown)
    }

    static func figurePath(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGPath {
        var t = figureTransform(inBody: body, small: small, yDown: yDown)
        return Sailboat.path.copy(using: &t)!
    }

    static func foldsPath(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGPath {
        var t = figureTransform(inBody: body, small: small, yDown: yDown)
        return folds.copy(using: &t)!
    }
}
