import SwiftUI

public enum CentralIconName: Sendable, Equatable {
    case homeLine
    case chatBubbles
    case peopleCircle
    case magnifyingGlass
    case voiceMid
}

/// Native rendering of the Central Icons paths used by Taisa's primary navigation.
public struct CentralIcon: View {
    private let name: CentralIconName

    public init(_ name: CentralIconName) {
        self.name = name
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            let transform = CGAffineTransform(
                translationX: (size.width - 24 * scale) / 2,
                y: (size.height - 24 * scale) / 2
            ).scaledBy(x: scale, y: scale)
            context.stroke(
                path.applying(transform),
                with: .foreground,
                style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }

    private var path: Path {
        switch name {
        case .homeLine: homeLine
        case .chatBubbles: chatBubbles
        case .peopleCircle: peopleCircle
        case .magnifyingGlass: magnifyingGlass
        case .voiceMid: voiceMid
        }
    }

    private var homeLine: Path {
        var path = Path()
        path.move(to: CGPoint(x: 4, y: 10.28))
        path.addCurve(to: CGPoint(x: 5.77, y: 6.56), control1: CGPoint(x: 4, y: 8.57), control2: CGPoint(x: 4.44, y: 7.64))
        path.addLine(to: CGPoint(x: 8.97, y: 3.96))
        path.addCurve(to: CGPoint(x: 15.03, y: 3.96), control1: CGPoint(x: 10.9, y: 2.4), control2: CGPoint(x: 13.1, y: 2.4))
        path.addLine(to: CGPoint(x: 18.23, y: 6.56))
        path.addCurve(to: CGPoint(x: 20, y: 10.28), control1: CGPoint(x: 19.56, y: 7.64), control2: CGPoint(x: 20, y: 8.57))
        path.addLine(to: CGPoint(x: 20, y: 15.2))
        path.addCurve(to: CGPoint(x: 15.2, y: 20), control1: CGPoint(x: 20, y: 18.4), control2: CGPoint(x: 18.4, y: 20))
        path.addLine(to: CGPoint(x: 8.8, y: 20))
        path.addCurve(to: CGPoint(x: 4, y: 15.2), control1: CGPoint(x: 5.6, y: 20), control2: CGPoint(x: 4, y: 18.4))
        path.closeSubpath()
        path.move(to: CGPoint(x: 8, y: 16)); path.addLine(to: CGPoint(x: 16, y: 16))
        return path
    }

    private var chatBubbles: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 10, y: 11, width: 11, height: 10))
        path.move(to: CGPoint(x: 20.63, y: 17.82)); path.addCurve(to: CGPoint(x: 20.39, y: 20.71), control1: CGPoint(x: 20.27, y: 18.65), control2: CGPoint(x: 19.96, y: 19.56))
        path.move(to: CGPoint(x: 16.81, y: 8)); path.addCurve(to: CGPoint(x: 10, y: 3), control1: CGPoint(x: 16.08, y: 5.13), control2: CGPoint(x: 13.31, y: 3))
        path.addCurve(to: CGPoint(x: 3, y: 9.5), control1: CGPoint(x: 6.13, y: 3), control2: CGPoint(x: 3, y: 5.91))
        path.addCurve(to: CGPoint(x: 4.07, y: 14.8), control1: CGPoint(x: 3, y: 11.17), control2: CGPoint(x: 4.35, y: 13.95))
        path.move(to: CGPoint(x: 3.78, y: 15.62)); path.addCurve(to: CGPoint(x: 7, y: 15.37), control1: CGPoint(x: 4.58, y: 15.57), control2: CGPoint(x: 6.08, y: 15.15))
        return path
    }

    private var peopleCircle: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
        path.addEllipse(in: CGRect(x: 9, y: 7, width: 6, height: 6))
        path.move(to: CGPoint(x: 6.12, y: 18.81))
        path.addCurve(to: CGPoint(x: 17.88, y: 18.81), control1: CGPoint(x: 8.78, y: 15.38), control2: CGPoint(x: 15.22, y: 15.38))
        return path
    }

    private var magnifyingGlass: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
        path.move(to: CGPoint(x: 16.05, y: 16.05))
        path.addLine(to: CGPoint(x: 20, y: 20))
        return path
    }

    private var voiceMid: Path {
        var path = Path()
        for segment in [
            (CGPoint(x: 8, y: 6), CGPoint(x: 8, y: 18)),
            (CGPoint(x: 4, y: 11), CGPoint(x: 4, y: 13)),
            (CGPoint(x: 12, y: 10), CGPoint(x: 12, y: 14)),
            (CGPoint(x: 16, y: 8), CGPoint(x: 16, y: 16)),
            (CGPoint(x: 20, y: 11), CGPoint(x: 20, y: 13)),
        ] {
            path.move(to: segment.0)
            path.addLine(to: segment.1)
        }
        return path
    }
}
