import AppIntents

struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "在 Together 新建任务"
    static let description = IntentDescription("打开 Together，在今天列表中创建一个可确认的任务草稿。")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "任务标题",
        description: "可选的一行任务标题",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var taskTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("在 Together 新建 \(\.$taskTitle)")
    }

    func perform() async throws -> some IntentResult {
        _ = await AppIntentHandoffCenter.shared.enqueueTaskCreation(title: taskTitle)
        return .result()
    }
}

struct TogetherAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "在 \(.applicationName) 新建任务",
                "用 \(.applicationName) 添加待办",
                "用 \(.applicationName) 记一项",
            ],
            shortTitle: "新建任务",
            systemImageName: "plus"
        )
    }
}
