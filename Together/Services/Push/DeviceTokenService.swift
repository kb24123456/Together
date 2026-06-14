import Foundation
import os

/// APNs Device Token 注册服务
actor DeviceTokenService {
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "DeviceToken")

    func registerToken(_ tokenData: Data) async {
        logger.debug("device token registration skipped; bytes=\(tokenData.count)")
    }

    func unregisterToken(_ tokenData: Data) async {
        logger.debug("device token unregister skipped; bytes=\(tokenData.count)")
    }
}
