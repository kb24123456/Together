import Foundation

enum MascotSurface: Hashable, Sendable {
    case home
    case editor(UUID)
}

/// Keeps the editor in charge until its native dismissal has finished.
struct MascotPlaybackOwnership {
    private(set) var editorID: UUID?
    private(set) var isReturning = false
    private(set) var hasArrivedAtEditor = false

    init() {}

    var surface: MascotSurface {
        editorID.map(MascotSurface.editor) ?? .home
    }

    var isEntering: Bool {
        editorID != nil && !hasArrivedAtEditor && !isReturning
    }

    @discardableResult
    mutating func beginEditing(id: UUID) -> Bool {
        if let editorID { return editorID == id }
        editorID = id
        hasArrivedAtEditor = false
        return true
    }

    /// The rendered artwork, rather than the page appearance, confirms arrival.
    @discardableResult
    mutating func arriveAtEditor(id: UUID) -> Bool {
        guard editorID == id, !isReturning, !hasArrivedAtEditor else { return false }
        hasArrivedAtEditor = true
        return true
    }

    /// Call only after saving succeeds or cancellation commits to dismissal.
    @discardableResult
    mutating func beginReturn(id: UUID) -> Bool {
        guard editorID == id else { return false }
        isReturning = true
        return true
    }

    /// Interactive dismissals may finish without an explicit beginReturn call.
    @discardableResult
    mutating func finishEditing(id: UUID) -> Bool {
        guard editorID == id else { return false }
        editorID = nil
        isReturning = false
        hasArrivedAtEditor = false
        return true
    }

    func acceptsInput(from source: MascotSurface) -> Bool {
        source == surface && !isReturning
    }
}
