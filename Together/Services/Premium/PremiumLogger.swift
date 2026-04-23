import OSLog

/// Phase 2 / Session A 共享的 OSLog logger。subsystem `com.pigdog.Together`, category `Premium`。
///
/// Console.app 过滤：`subsystem:com.pigdog.Together category:Premium`
let premiumLogger = Logger(subsystem: "com.pigdog.Together", category: "Premium")
