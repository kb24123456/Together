import Foundation
#if os(iOS)
import UIKit
#endif

enum SoloDevicePlatform: String, Codable, Hashable, Sendable {
    case iphone
    case ipad
    case mac

    static var current: SoloDevicePlatform {
        #if os(macOS)
        return .mac
        #else
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
        #else
        return .iphone
        #endif
        #endif
    }
}
