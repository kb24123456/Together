import Foundation
import CoreGraphics

/// The approved 40pt drawing, sampled once for Core Animation, never in root state.
nonisolated enum MascotConfirmationMotion {
    struct Pose: Equatable {
        var main: [CGPoint]
        var secondary: [CGPoint]
        var secondaryOpacity: CGFloat = 1
    }

    static let idle = Pose(
        main: [CGPoint(x: 16.52, y: 13.32), CGPoint(x: 16.52, y: 16.17), CGPoint(x: 16.52, y: 19.02)],
        secondary: [CGPoint(x: 25.98, y: 13.32), CGPoint(x: 25.98, y: 19.02)]
    )
    static let start = CGPoint(x: 13, y: 20)
    static let corner = CGPoint(x: 18.2, y: 25.1)
    static let end = CGPoint(x: 27.5, y: 13.8)
    static let check = Pose(main: [start, corner, end], secondary: [start, start], secondaryOpacity: 0)
    static let faceHoldDuration: TimeInterval = 0.18
    static let eraseDuration: TimeInterval = 0.20
    static let restorationDuration: TimeInterval = 0.36
    static let entranceDuration: TimeInterval = 0.60
    static let retractionDelay = restorationDuration + faceHoldDuration

    static func entering(at time: TimeInterval, from initial: Pose = idle) -> Pose {
        if time >= entranceDuration { return check }
        let seed = Pose(main: [start, start, start], secondary: [start, start])
        if time < 0.32 {
            return interpolate(initial, seed, progress: smooth((time - faceHoldDuration) / 0.14))
        }
        let progress = smooth((time - 0.32) / 0.28)
        let short = hypot(corner.x - start.x, corner.y - start.y)
        let long = hypot(end.x - corner.x, end.y - corner.y)
        let distance = progress * (short + long)
        let points: [CGPoint]
        if distance <= short {
            let tip = mix(start, corner, distance / short)
            points = [start, tip, tip]
        } else {
            points = [start, corner, mix(corner, end, (distance - short) / long)]
        }
        return Pose(main: points, secondary: seed.secondary, secondaryOpacity: 0)
    }

    /// Reverse the visible stroke, then unfold its seed into eyes. The starting
    /// pose can be a partial drawing captured during an interruption.
    static func restoring(at time: TimeInterval, from initial: Pose = check) -> Pose {
        if time <= 0 { return initial }
        if time >= restorationDuration { return idle }
        let origin = initial.main[0]
        let seed = Pose(main: [origin, origin, origin], secondary: [origin, origin])
        if time >= eraseDuration {
            return interpolate(seed, idle, progress: smooth((time - eraseDuration) / 0.16))
        }
        let progress = smooth(time / eraseDuration)
        let short = hypot(initial.main[1].x - origin.x, initial.main[1].y - origin.y)
        let long = hypot(initial.main[2].x - initial.main[1].x, initial.main[2].y - initial.main[1].y)
        let distance = (1 - progress) * (short + long)
        let points: [CGPoint]
        if distance <= short || long == 0 {
            let tip = short > 0 ? mix(origin, initial.main[1], distance / short) : origin
            points = [origin, tip, tip]
        } else {
            points = [origin, initial.main[1], mix(initial.main[1], initial.main[2], (distance - short) / long)]
        }
        return Pose(main: points, secondary: initial.secondary.map { mix($0, origin, progress) },
                    secondaryOpacity: initial.secondaryOpacity)
    }

    static func interpolate(_ from: Pose, _ to: Pose, progress: CGFloat) -> Pose {
        Pose(main: zip(from.main, to.main).map { mix($0, $1, progress) },
             secondary: zip(from.secondary, to.secondary).map { mix($0, $1, progress) },
             secondaryOpacity: from.secondaryOpacity + (to.secondaryOpacity - from.secondaryOpacity) * progress)
    }

    static func smooth(_ value: Double) -> CGFloat {
        let x = min(1, max(0, value))
        return CGFloat(x * x * x * (x * (x * 6 - 15) + 10))
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ progress: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
    }
}
