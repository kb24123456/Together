import Foundation

enum LoadableState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
