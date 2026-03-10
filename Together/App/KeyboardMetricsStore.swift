import Foundation
import Observation
import CoreGraphics

@MainActor
@Observable
final class KeyboardMetricsStore {
    private(set) var currentHeight: CGFloat = 0
    private(set) var cachedHeight: CGFloat = 0
    private(set) var hasMeasuredSoftwareKeyboard = false

    var reservedHeight: CGFloat {
        currentHeight > 0 ? currentHeight : cachedHeight
    }

    func updateVisibleHeight(_ height: CGFloat) {
        let sanitizedHeight = max(0, height)
        currentHeight = sanitizedHeight

        if sanitizedHeight > 0 {
            cachedHeight = sanitizedHeight
            hasMeasuredSoftwareKeyboard = true
        }
    }

    func keyboardDidHide() {
        currentHeight = 0
    }
}
