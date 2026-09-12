import Foundation
import CoreGraphics

nonisolated struct MascotNoticeRequest: Equatable, Sendable {
    let id: UUID
    let message: String
    let announcement: String
}

/// Result replacement and stale completion rejection, separate from navigation.
nonisolated struct MascotNoticeState {
    private(set) var request: MascotNoticeRequest?
    private(set) var isDismissing = false

    mutating func replace(with request: MascotNoticeRequest) {
        self.request = request
        isDismissing = false
    }

    @discardableResult
    mutating func dismiss(id: UUID) -> Bool {
        guard request?.id == id, !isDismissing else { return false }
        isDismissing = true
        return true
    }

    @discardableResult
    mutating func finish(id: UUID) -> Bool {
        guard request?.id == id, isDismissing else { return false }
        cancel()
        return true
    }

    mutating func cancel() {
        request = nil
        isDismissing = false
    }
}

nonisolated enum MascotNoticeGeometry {
    /// The original 512px artwork has a 368px body centered at (256, 240).
    static func body(in canvas: CGRect) -> CGRect {
        CGRect(x: canvas.minX + canvas.width * 72 / 512,
               y: canvas.minY + canvas.height * 56 / 512,
               width: canvas.width * 368 / 512, height: canvas.height * 368 / 512)
    }

    static func expanded(from body: CGRect, in bounds: CGRect,
                         safeInsets: CGFloat, contentWidth: CGFloat) -> CGRect {
        let available = max(body.width, bounds.width - safeInsets * 2)
        let width = min(max(body.width, contentWidth), available)
        return CGRect(x: bounds.midX - width / 2, y: body.minY,
                      width: width, height: body.height)
    }
}
