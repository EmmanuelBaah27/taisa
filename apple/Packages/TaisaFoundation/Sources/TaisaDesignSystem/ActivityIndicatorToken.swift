import CoreGraphics
import SwiftUI

public enum TaisaActivityIndicatorMetric {
    public static let width: CGFloat = 44
    public static let height: CGFloat = 24
    public static let barWidth: CGFloat = 12
    public static let activeBarHeight: CGFloat = 22
    public static let restingBarHeight: CGFloat = 10
    public static let barSpacing: CGFloat = 2
    public static let barRadius: CGFloat = 3
}

public extension TaisaMotion {
    static let activityCycle: Double = 2
    static let activityStagger: Double = 0.18
    static var activityAnimation: Animation {
        .easeInOut(duration: activityCycle / 2).repeatForever(autoreverses: true)
    }
}
