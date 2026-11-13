import SwiftUI

public enum CentralIconName: Sendable, Equatable {
    case homeLine
    case chatBubbles
    case peopleCircle
    case magnifyingGlass
    case voiceMid
    case cross
    case keyboard
    case arrowUp
    case arrowDown
    case pause
    case play
    case chevronLeft
    case chevronDown
    case exclamationCircle
    case circleInfo
    case thumbsUp
    case thumbsDown
    case copy
    case edit
    case action
    case checklist
    case add
    case incomplete
    case completeAction
    case completed
    case drop
    case delete
    case undo
    case evidence
    case history
    case goal
    case milestone
    case warning
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
            if let filledPath {
                context.fill(filledPath.applying(transform), with: .foreground)
            }
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
        case .cross: cross
        case .keyboard: keyboard
        case .arrowUp: arrowUp
        case .arrowDown: arrowDown
        case .pause: pause
        case .play: play
        case .chevronLeft: chevronLeft
        case .chevronDown: chevronDown
        case .exclamationCircle: exclamationCircle
        case .circleInfo: circleInfo
        case .thumbsUp: thumbsUp
        case .thumbsDown: thumbsDown
        case .copy: copy
        case .edit: edit
        case .action, .checklist: checklist
        case .add: add
        case .incomplete: incomplete
        case .completeAction: completeAction
        case .completed: completed
        case .drop: drop
        case .delete: delete
        case .undo: undo
        case .evidence: evidence
        case .history: history
        case .goal: goal
        case .milestone: milestone
        case .warning: warning
        }
    }

    private var filledPath: Path? {
        guard name == .circleInfo else { return nil }
        var path = Path()
        path.addEllipse(in: CGRect(x: 11.375, y: 7.375, width: 1.25, height: 1.25))
        return path
    }

    private var checklist: Path {
        var p = Path()
        p.move(to: .init(x: 13, y: 16)); p.addLine(to: .init(x: 20, y: 16))
        p.move(to: .init(x: 13, y: 8)); p.addLine(to: .init(x: 20, y: 8))
        p.move(to: .init(x: 4, y: 9)); p.addLine(to: .init(x: 5.5, y: 10)); p.addLine(to: .init(x: 8.5, y: 6))
        p.move(to: .init(x: 4, y: 17)); p.addLine(to: .init(x: 5.5, y: 18)); p.addLine(to: .init(x: 8.5, y: 14))
        return p
    }

    private var add: Path {
        var p = Path()
        p.move(to: .init(x: 12, y: 5.5)); p.addLine(to: .init(x: 12, y: 18.5))
        p.move(to: .init(x: 5.5, y: 12)); p.addLine(to: .init(x: 18.5, y: 12))
        return p
    }

    private var incomplete: Path {
        var p = Path()
        for angle in stride(from: 0.0, to: 360.0, by: 22.5) {
            let radians = angle * .pi / 180
            let point = CGPoint(x: 12 + 9 * cos(radians), y: 12 + 9 * sin(radians))
            p.move(to: point); p.addLine(to: CGPoint(x: point.x + 0.01, y: point.y + 0.01))
        }
        return p
    }

    private var completeAction: Path {
        var p = Path(); p.addEllipse(in: .init(x: 3, y: 3, width: 18, height: 18)); return p
    }

    private var completed: Path {
        var p = completeAction
        p.move(to: .init(x: 8, y: 12.875)); p.addLine(to: .init(x: 10.625, y: 15.5)); p.addLine(to: .init(x: 15, y: 9))
        return p
    }

    private var drop: Path {
        var p = Path()
        p.move(to: .init(x: 20, y: 8)); p.addLine(to: .init(x: 20, y: 15.2)); p.addCurve(to: .init(x: 15.2, y: 20), control1: .init(x: 20, y: 18.4), control2: .init(x: 18.4, y: 20)); p.addLine(to: .init(x: 8.8, y: 20)); p.addCurve(to: .init(x: 4, y: 15.2), control1: .init(x: 5.6, y: 20), control2: .init(x: 4, y: 18.4)); p.addLine(to: .init(x: 4, y: 8))
        p.addRect(.init(x: 3, y: 4, width: 18, height: 4))
        p.move(to: .init(x: 10, y: 12)); p.addLine(to: .init(x: 14, y: 12))
        return p
    }

    private var delete: Path {
        var p = Path()
        p.move(to: .init(x: 5, y: 6.5)); p.addLine(to: .init(x: 5.807, y: 18.206)); p.addCurve(to: .init(x: 8.8, y: 21), control1: .init(x: 5.916, y: 19.779), control2: .init(x: 7.223, y: 21)); p.addLine(to: .init(x: 15.2, y: 21)); p.addCurve(to: .init(x: 18.193, y: 18.206), control1: .init(x: 16.777, y: 21), control2: .init(x: 18.084, y: 19.779)); p.addLine(to: .init(x: 19, y: 6.5))
        p.move(to: .init(x: 10, y: 11)); p.addLine(to: .init(x: 10, y: 16)); p.move(to: .init(x: 14, y: 11)); p.addLine(to: .init(x: 14, y: 16)); p.move(to: .init(x: 3.5, y: 6)); p.addLine(to: .init(x: 20.5, y: 6))
        p.move(to: .init(x: 8.071, y: 5.746)); p.addCurve(to: .init(x: 15.929, y: 5.746), control1: .init(x: 8.423, y: 3.897), control2: .init(x: 15.577, y: 3.897))
        return p
    }

    private var undo: Path {
        var p = Path()
        p.move(to: .init(x: 6.5, y: 5)); p.addLine(to: .init(x: 3.56, y: 7.94)); p.addCurve(to: .init(x: 3.56, y: 10.06), control1: .init(x: 2.975, y: 8.525), control2: .init(x: 2.975, y: 9.475)); p.addLine(to: .init(x: 6.5, y: 13))
        p.move(to: .init(x: 4, y: 9)); p.addLine(to: .init(x: 16.5, y: 9)); p.addCurve(to: .init(x: 16.5, y: 18), control1: .init(x: 22.5, y: 9), control2: .init(x: 22.5, y: 18)); p.addLine(to: .init(x: 12, y: 18))
        return p
    }

    private var evidence: Path {
        var p = Path()
        p.move(to: .init(x: 12.172, y: 3)); p.addLine(to: .init(x: 8, y: 3)); p.addCurve(to: .init(x: 5, y: 6), control1: .init(x: 6.343, y: 3), control2: .init(x: 5, y: 4.343)); p.addLine(to: .init(x: 5, y: 18)); p.addCurve(to: .init(x: 8, y: 21), control1: .init(x: 5, y: 19.657), control2: .init(x: 6.343, y: 21)); p.addLine(to: .init(x: 16, y: 21)); p.addCurve(to: .init(x: 19, y: 18), control1: .init(x: 17.657, y: 21), control2: .init(x: 19, y: 19.657)); p.addLine(to: .init(x: 19, y: 9.828)); p.addLine(to: .init(x: 12.172, y: 3));
        p.move(to: .init(x: 13, y: 3.5)); p.addLine(to: .init(x: 13, y: 7)); p.addCurve(to: .init(x: 15, y: 9), control1: .init(x: 13, y: 8.105), control2: .init(x: 13.895, y: 9)); p.addLine(to: .init(x: 18.5, y: 9)); p.move(to: .init(x: 9, y: 13)); p.addLine(to: .init(x: 12, y: 13)); p.move(to: .init(x: 9, y: 17)); p.addLine(to: .init(x: 15.5, y: 17))
        return p
    }

    private var history: Path {
        var p = Path()
        p.move(to: .init(x: 3, y: 5)); p.addLine(to: .init(x: 3, y: 9)); p.addLine(to: .init(x: 7, y: 9))
        p.move(to: .init(x: 3.512, y: 15)); p.addCurve(to: .init(x: 3.706, y: 8.5), control1: .init(x: 1.8, y: 10), control2: .init(x: 2.4, y: 9)); p.addCurve(to: .init(x: 12, y: 3), control1: .init(x: 5.071, y: 5.268), control2: .init(x: 8.27, y: 3)); p.addEllipse(in: .init(x: 3, y: 3, width: 18, height: 18)); p.move(to: .init(x: 12, y: 8)); p.addLine(to: .init(x: 12, y: 12)); p.addLine(to: .init(x: 15, y: 15))
        return p
    }

    private var goal: Path {
        var p = Path(); p.addEllipse(in: .init(x: 3, y: 3, width: 18, height: 18)); p.addEllipse(in: .init(x: 7, y: 7, width: 10, height: 10)); p.addEllipse(in: .init(x: 11, y: 11, width: 2, height: 2)); return p
    }

    private var milestone: Path {
        var p = Path(); p.move(to: .init(x: 5, y: 15)); p.addLine(to: .init(x: 5, y: 4)); p.addCurve(to: .init(x: 6, y: 3), control1: .init(x: 5, y: 3.448), control2: .init(x: 5.448, y: 3)); p.addLine(to: .init(x: 19.132, y: 3)); p.addLine(to: .init(x: 17.37, y: 8.445)); p.addLine(to: .init(x: 19.132, y: 15)); p.addLine(to: .init(x: 5, y: 15)); p.addLine(to: .init(x: 5, y: 21)); return p
    }

    private var warning: Path {
        exclamationCircle
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

    private var cross: Path {
        var path = Path(); path.move(to: .init(x: 6, y: 6)); path.addLine(to: .init(x: 18, y: 18)); path.move(to: .init(x: 18, y: 6)); path.addLine(to: .init(x: 6, y: 18)); return path
    }

    private var keyboard: Path {
        var path = Path(); path.addRoundedRect(in: .init(x: 3, y: 6, width: 18, height: 13), cornerSize: .init(width: 2, height: 2));
        for x in stride(from: CGFloat(6), through: 18, by: 4) { path.move(to: .init(x: x, y: 10)); path.addLine(to: .init(x: x, y: 10.1)) }
        path.move(to: .init(x: 7, y: 15)); path.addLine(to: .init(x: 17, y: 15)); return path
    }

    private var arrowUp: Path {
        var path = Path(); path.move(to: .init(x: 12, y: 20)); path.addLine(to: .init(x: 12, y: 5)); path.move(to: .init(x: 6, y: 11)); path.addLine(to: .init(x: 12, y: 5)); path.addLine(to: .init(x: 18, y: 11)); return path
    }

    private var arrowDown: Path {
        var path = Path(); path.move(to: .init(x: 18, y: 14)); path.addLine(to: .init(x: 12, y: 20)); path.addLine(to: .init(x: 6, y: 14)); path.move(to: .init(x: 12, y: 19)); path.addLine(to: .init(x: 12, y: 4)); return path
    }

    private var pause: Path {
        var path = Path(); path.move(to: .init(x: 8, y: 6)); path.addLine(to: .init(x: 8, y: 18)); path.move(to: .init(x: 16, y: 6)); path.addLine(to: .init(x: 16, y: 18)); return path
    }

    private var play: Path {
        var path = Path(); path.move(to: .init(x: 8, y: 5)); path.addLine(to: .init(x: 19, y: 12)); path.addLine(to: .init(x: 8, y: 19)); path.closeSubpath(); return path
    }

    private var chevronDown: Path {
        var path = Path(); path.move(to: .init(x: 5, y: 9)); path.addLine(to: .init(x: 12, y: 16)); path.addLine(to: .init(x: 19, y: 9)); return path
    }

    private var chevronLeft: Path {
        var path = Path(); path.move(to: .init(x: 15, y: 5)); path.addLine(to: .init(x: 8, y: 12)); path.addLine(to: .init(x: 15, y: 19)); return path
    }

    private var exclamationCircle: Path {
        var path = Path(); path.addEllipse(in: .init(x: 3, y: 3, width: 18, height: 18)); path.move(to: .init(x: 12, y: 7)); path.addLine(to: .init(x: 12, y: 13)); path.move(to: .init(x: 12, y: 17)); path.addLine(to: .init(x: 12, y: 17.1)); return path
    }

    private var circleInfo: Path {
        var path = Path()
        path.move(to: CGPoint(x: 10.75, y: 11))
        path.addLine(to: CGPoint(x: 12, y: 11))
        path.addLine(to: CGPoint(x: 12, y: 16.25))
        path.addEllipse(in: CGRect(x: 2.75, y: 2.75, width: 18.5, height: 18.5))
        return path
    }

    private var copy: Path {
        var path = Path()
        path.move(to: CGPoint(x: 15.25, y: 8.75))
        path.addLine(to: CGPoint(x: 15.25, y: 4))
        path.addCurve(to: CGPoint(x: 14, y: 2.75), control1: CGPoint(x: 15.25, y: 3.31), control2: CGPoint(x: 14.69, y: 2.75))
        path.addLine(to: CGPoint(x: 4, y: 2.75))
        path.addCurve(to: CGPoint(x: 2.75, y: 4), control1: CGPoint(x: 3.31, y: 2.75), control2: CGPoint(x: 2.75, y: 3.31))
        path.addLine(to: CGPoint(x: 2.75, y: 14))
        path.addCurve(to: CGPoint(x: 4, y: 15.25), control1: CGPoint(x: 2.75, y: 14.69), control2: CGPoint(x: 3.31, y: 15.25))
        path.addLine(to: CGPoint(x: 8.75, y: 15.25))
        path.move(to: CGPoint(x: 10, y: 8.75))
        path.addLine(to: CGPoint(x: 20, y: 8.75))
        path.addCurve(to: CGPoint(x: 21.25, y: 10), control1: CGPoint(x: 20.69, y: 8.75), control2: CGPoint(x: 21.25, y: 9.31))
        path.addLine(to: CGPoint(x: 21.25, y: 20))
        path.addCurve(to: CGPoint(x: 20, y: 21.25), control1: CGPoint(x: 21.25, y: 20.69), control2: CGPoint(x: 20.69, y: 21.25))
        path.addLine(to: CGPoint(x: 10, y: 21.25))
        path.addCurve(to: CGPoint(x: 8.75, y: 20), control1: CGPoint(x: 9.31, y: 21.25), control2: CGPoint(x: 8.75, y: 20.69))
        path.addLine(to: CGPoint(x: 8.75, y: 10))
        path.addCurve(to: CGPoint(x: 10, y: 8.75), control1: CGPoint(x: 8.75, y: 9.31), control2: CGPoint(x: 9.31, y: 8.75))
        path.closeSubpath()
        return path
    }

    private var edit: Path {
        var path = Path()
        path.move(to: CGPoint(x: 18.91, y: 3.41))
        path.addLine(to: CGPoint(x: 20.59, y: 5.09))
        path.addCurve(to: CGPoint(x: 20.59, y: 7.91), control1: CGPoint(x: 21.37, y: 5.87), control2: CGPoint(x: 21.37, y: 7.13))
        path.addLine(to: CGPoint(x: 7.84, y: 20.66))
        path.addCurve(to: CGPoint(x: 6.42, y: 21.25), control1: CGPoint(x: 7.46, y: 21.04), control2: CGPoint(x: 6.95, y: 21.25))
        path.addLine(to: CGPoint(x: 2.75, y: 21.25))
        path.addLine(to: CGPoint(x: 2.75, y: 17.58))
        path.addCurve(to: CGPoint(x: 3.34, y: 16.16), control1: CGPoint(x: 2.75, y: 17.05), control2: CGPoint(x: 2.96, y: 16.54))
        path.addLine(to: CGPoint(x: 16.09, y: 3.41))
        path.addCurve(to: CGPoint(x: 18.91, y: 3.41), control1: CGPoint(x: 16.87, y: 2.63), control2: CGPoint(x: 18.13, y: 2.63))
        path.closeSubpath()
        path.move(to: CGPoint(x: 13.25, y: 6.25))
        path.addLine(to: CGPoint(x: 17.75, y: 10.75))
        return path
    }

    private var thumbsUp: Path {
        var path = Path()
        path.move(to: CGPoint(x: 7, y: 11))
        path.addLine(to: CGPoint(x: 4, y: 11))
        path.addCurve(to: CGPoint(x: 3, y: 12), control1: CGPoint(x: 3.45, y: 11), control2: CGPoint(x: 3, y: 11.45))
        path.addLine(to: CGPoint(x: 3, y: 19))
        path.addCurve(to: CGPoint(x: 4, y: 20), control1: CGPoint(x: 3, y: 19.55), control2: CGPoint(x: 3.45, y: 20))
        path.addLine(to: CGPoint(x: 7, y: 20))
        path.move(to: CGPoint(x: 7, y: 11))
        path.addLine(to: CGPoint(x: 7, y: 20))
        path.move(to: CGPoint(x: 7, y: 11))
        path.addLine(to: CGPoint(x: 11, y: 3))
        path.addLine(to: CGPoint(x: 11.62, y: 3))
        path.addCurve(to: CGPoint(x: 13.59, y: 5.31), control1: CGPoint(x: 12.84, y: 3), control2: CGPoint(x: 13.78, y: 4.10))
        path.addLine(to: CGPoint(x: 13.02, y: 9))
        path.addLine(to: CGPoint(x: 18.06, y: 9))
        path.addCurve(to: CGPoint(x: 21.04, y: 12.41), control1: CGPoint(x: 19.88, y: 9), control2: CGPoint(x: 21.28, y: 10.60))
        path.addLine(to: CGPoint(x: 20.35, y: 17.41))
        path.addCurve(to: CGPoint(x: 17.38, y: 20), control1: CGPoint(x: 20.15, y: 18.89), control2: CGPoint(x: 18.88, y: 20))
        path.addLine(to: CGPoint(x: 7, y: 20))
        return path
    }

    private var thumbsDown: Path {
        var path = Path()
        path.move(to: CGPoint(x: 17, y: 13))
        path.addLine(to: CGPoint(x: 20, y: 13))
        path.addCurve(to: CGPoint(x: 21, y: 12), control1: CGPoint(x: 20.55, y: 13), control2: CGPoint(x: 21, y: 12.55))
        path.addLine(to: CGPoint(x: 21, y: 5))
        path.addCurve(to: CGPoint(x: 20, y: 4), control1: CGPoint(x: 21, y: 4.45), control2: CGPoint(x: 20.55, y: 4))
        path.addLine(to: CGPoint(x: 17, y: 4))
        path.move(to: CGPoint(x: 17, y: 13))
        path.addLine(to: CGPoint(x: 17, y: 4))
        path.move(to: CGPoint(x: 17, y: 13))
        path.addLine(to: CGPoint(x: 13.30, y: 20.45))
        path.addCurve(to: CGPoint(x: 10.45, y: 18.69), control1: CGPoint(x: 12.59, y: 21.88), control2: CGPoint(x: 10.26, y: 20.20))
        path.addLine(to: CGPoint(x: 11.02, y: 15))
        path.addLine(to: CGPoint(x: 5.99, y: 15))
        path.addCurve(to: CGPoint(x: 3.03, y: 11.59), control1: CGPoint(x: 4.18, y: 15), control2: CGPoint(x: 2.78, y: 13.40))
        path.addLine(to: CGPoint(x: 3.71, y: 6.59))
        path.addCurve(to: CGPoint(x: 6.67, y: 4), control1: CGPoint(x: 3.91, y: 5.11), control2: CGPoint(x: 5.17, y: 4))
        path.addLine(to: CGPoint(x: 17, y: 4))
        return path
    }
}
