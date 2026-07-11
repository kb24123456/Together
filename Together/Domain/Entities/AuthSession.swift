import Foundation

enum AppMode: String, CaseIterable, Hashable, Sendable {
    case single
}

enum WorkspaceSelection: String, CaseIterable, Hashable, Sendable {
    case single

    var appMode: AppMode {
        .single
    }
}

struct SpaceContext: Hashable, Sendable {
    var singleSpace: Space?
    var activeMode: AppMode
    var availableModes: [AppMode]

    var activeSpace: Space? {
        singleSpace
    }

    var availableSpaces: [Space] {
        [singleSpace].compactMap { $0 }
    }
}
