import CoreGraphics
import Foundation
import UIKit

struct HomeFocusFrozenGeometry: Equatable {
    let subject: HomeFocusSubject
    let sourceFrame: CGRect
    let viewportFrame: CGRect
    let availableFrame: CGRect
}

struct HomeFocusGeometryRegistry {
    private(set) var windowID: UUID
    private(set) var frozenGeometry: HomeFocusFrozenGeometry?

    private var taskFrames: [HomeFocusSubject: CGRect] = [:]
    private var viewportFrame: CGRect?
    private var availableFrame: CGRect?

    init(windowID: UUID) {
        self.windowID = windowID
    }

    mutating func replaceWindow(with windowID: UUID) {
        guard self.windowID != windowID else { return }
        self.windowID = windowID
        taskFrames.removeAll()
        viewportFrame = nil
        availableFrame = nil
        frozenGeometry = nil
    }

    @discardableResult
    mutating func recordTaskFrame(subject: HomeFocusSubject, frame: CGRect, windowID: UUID) -> Bool {
        guard case .detail = subject else { return false }
        guard accepts(frame, from: windowID) else { return false }
        taskFrames[subject] = frame
        return true
    }

    @discardableResult
    mutating func recordViewportFrame(_ frame: CGRect, windowID: UUID) -> Bool {
        guard accepts(frame, from: windowID) else { return false }
        viewportFrame = frame
        return true
    }

    @discardableResult
    mutating func recordAvailableFrame(_ frame: CGRect, windowID: UUID) -> Bool {
        guard accepts(frame, from: windowID) else { return false }
        availableFrame = frame
        return true
    }

    func taskFrame(for subject: HomeFocusSubject) -> CGRect? {
        taskFrames[subject]
    }

    mutating func freeze(for subject: HomeFocusSubject) -> HomeFocusFrozenGeometry? {
        if let frozenGeometry {
            return frozenGeometry.subject == subject ? frozenGeometry : nil
        }

        guard let sourceFrame = sourceFrame(for: subject),
              let viewportFrame,
              let availableFrame
        else { return nil }

        let geometry = HomeFocusFrozenGeometry(
            subject: subject,
            sourceFrame: sourceFrame,
            viewportFrame: viewportFrame,
            availableFrame: availableFrame
        )
        frozenGeometry = geometry
        return geometry
    }

    mutating func clearFrozenGeometry() {
        frozenGeometry = nil
    }

    private func sourceFrame(for subject: HomeFocusSubject) -> CGRect? {
        switch subject {
        case .detail:
            taskFrames[subject]
        case .creation:
            // Creation materializes at its stable focus frame. The add button is
            // a causal trigger, not the visual identity of the task surface.
            availableFrame.map { frame in
                CGRect(x: frame.midX - 1, y: frame.midY - 1, width: 2, height: 2)
            }
        }
    }

    private func accepts(_ frame: CGRect, from windowID: UUID) -> Bool {
        self.windowID == windowID && frame.isUsableForFocusPresentation
    }
}

enum HomeFocusGeometryPolicy {
    static func availableFrame(in bounds: CGRect, safeAreaInsets: UIEdgeInsets) -> CGRect {
        CGRect(
            x: bounds.minX + safeAreaInsets.left,
            y: bounds.minY + safeAreaInsets.top,
            width: max(0, bounds.width - safeAreaInsets.left - safeAreaInsets.right),
            height: max(0, bounds.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )
    }

    static func detailTargetFrame(
        sourceFrame: CGRect,
        proposedHeight: CGFloat,
        availableFrame: CGRect,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat
    ) -> CGRect {
        let bounded = availableFrame.insetBy(dx: horizontalMargin, dy: verticalMargin)
        let height = min(max(sourceFrame.height, proposedHeight), bounded.height)
        let maximumY = bounded.maxY - height
        let y = min(max(sourceFrame.minY, bounded.minY), maximumY)
        return CGRect(x: bounded.minX, y: y, width: bounded.width, height: height)
    }

    static func creationFocusFrame(
        proposedSize: CGSize,
        availableFrame: CGRect,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat
    ) -> CGRect {
        let bounded = availableFrame.insetBy(dx: horizontalMargin, dy: verticalMargin)
        let size = CGSize(
            width: min(max(0, proposedSize.width), bounded.width),
            height: min(max(0, proposedSize.height), bounded.height)
        )
        return CGRect(
            x: bounded.midX - size.width / 2,
            y: bounded.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func keyboardVerticalCorrection(
        cardFrame: CGRect,
        keyboardFrame: CGRect,
        availableFrame: CGRect,
        clearance: CGFloat
    ) -> CGFloat {
        guard cardFrame.maxX > keyboardFrame.minX,
              cardFrame.minX < keyboardFrame.maxX,
              keyboardFrame.minY < availableFrame.maxY
        else { return 0 }

        let allowedBottom = min(availableFrame.maxY - clearance, keyboardFrame.minY - clearance)
        let requiredShift = min(0, allowedBottom - cardFrame.maxY)
        let maximumUpwardShift = availableFrame.minY + clearance - cardFrame.minY
        return max(requiredShift, maximumUpwardShift)
    }

    static func isFullyVisible(_ frame: CGRect, in viewportFrame: CGRect) -> Bool {
        frame.isUsableForFocusPresentation && viewportFrame.contains(frame)
    }
}

private extension CGRect {
    var isUsableForFocusPresentation: Bool {
        minX.isFinite
            && minY.isFinite
            && width.isFinite
            && height.isFinite
            && width > 0
            && height > 0
    }
}
