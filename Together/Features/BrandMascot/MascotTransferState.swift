import Foundation
import CoreGraphics

struct MascotVisualTransition: Equatable, Sendable {
    let id: UUID
    let source: MascotSurface
    let destination: MascotSurface
}

/// Tracks only the visible handoff; navigation and editing retain their own ownership.
struct MascotTransferState {
    private(set) var settledSurface: MascotSurface = .home
    private(set) var transition: MascotVisualTransition?

    @discardableResult
    mutating func begin(from source: MascotSurface, to destination: MascotSurface) -> MascotVisualTransition {
        if let transition, transition.source == source, transition.destination == destination {
            return transition
        }
        let next = MascotVisualTransition(id: UUID(), source: source, destination: destination)
        transition = next
        return next
    }

    @discardableResult
    mutating func complete(id: UUID, cancelled: Bool) -> MascotSurface? {
        guard let transition, transition.id == id else { return nil }
        settledSurface = cancelled ? transition.source : transition.destination
        self.transition = nil
        return settledSurface
    }

    mutating func settle(at surface: MascotSurface) {
        transition = nil
        settledSurface = surface
    }
}

enum MascotTransferGeometry {
    /// Converts a local anchor to the presented controller's final frame, including scale.
    static func map(_ rect: CGRect, from bounds: CGRect, to frame: CGRect) -> CGRect? {
        guard isUsable(rect), isUsable(bounds), isUsable(frame) else { return nil }
        let scaleX = frame.size.width / bounds.size.width
        let scaleY = frame.size.height / bounds.size.height
        let mappedX = frame.origin.x + (rect.origin.x - bounds.origin.x) * scaleX
        let mappedY = frame.origin.y + (rect.origin.y - bounds.origin.y) * scaleY
        let mapped = CGRect(
            origin: CGPoint(x: mappedX, y: mappedY),
            size: CGSize(width: rect.size.width * scaleX, height: rect.size.height * scaleY)
        )
        return isUsable(mapped) ? mapped : nil
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }
}
