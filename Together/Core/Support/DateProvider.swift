import Foundation

/// 时间获取抽象。生产代码用 `SystemDateProvider`，测试用 `FixedDateProvider`。
/// 允许 Grace Period、Cache TTL 等时间敏感逻辑在测试中用确定值驱动。
protocol DateProvider: Sendable {
    func now() -> Date
}

struct SystemDateProvider: DateProvider {
    func now() -> Date { Date() }
}

/// 测试专用：返回固定时间。
struct FixedDateProvider: DateProvider {
    let fixed: Date
    func now() -> Date { fixed }
}
