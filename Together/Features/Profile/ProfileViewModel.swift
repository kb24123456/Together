import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let authService: AuthServiceProtocol
    private let relationshipService: RelationshipServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let itemRepository: ItemRepositoryProtocol
    private let projectRepository: ProjectRepositoryProtocol
    private let reminderScheduler: ReminderSchedulerProtocol

    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined

    init(
        sessionStore: SessionStore,
        authService: AuthServiceProtocol,
        relationshipService: RelationshipServiceProtocol,
        notificationService: NotificationServiceProtocol,
        itemRepository: ItemRepositoryProtocol,
        projectRepository: ProjectRepositoryProtocol,
        reminderScheduler: ReminderSchedulerProtocol
    ) {
        self.sessionStore = sessionStore
        self.authService = authService
        self.relationshipService = relationshipService
        self.notificationService = notificationService
        self.itemRepository = itemRepository
        self.projectRepository = projectRepository
        self.reminderScheduler = reminderScheduler
    }

    var currentUser: User? { sessionStore.currentUser }
    var currentSpace: Space? { sessionStore.currentSpace }
    var bindingState: BindingState { sessionStore.bindingState }
    var pairSpace: PairSpace? { sessionStore.currentPairSpace }
    var activeInvite: Invite? { sessionStore.activeInvite }

    var notificationSummary: String {
        switch notificationAuthorization {
        case .authorized:
            return "提醒已开启"
        case .denied:
            return "提醒未开启"
        case .notDetermined:
            return "尚未请求提醒权限"
        }
    }

    var taskUrgencyWindowMinutes: Int {
        sessionStore.currentUser?.preferences.taskUrgencyWindowMinutes ?? 30
    }

    let taskUrgencyOptions: [Int] = [10, 30, 60, 120]
    let quickTimePresetOptions: [Int] = Array(stride(from: 5, through: 180, by: 5))

    var quickTimePresetMinutes: [Int] {
        NotificationSettings.normalizedQuickTimePresetMinutes(
            sessionStore.currentUser?.preferences.quickTimePresetMinutes ?? NotificationSettings.defaultQuickTimePresetMinutes
        )
    }

    var snoozePresetSummary: String {
        let titles = quickTimePresetMinutes.map { minutes in
            if minutes >= 60, minutes.isMultiple(of: 60) {
                return "\(minutes / 60)小时后"
            }
            return "\(minutes)分钟后"
        }
        return titles.joined(separator: " / ")
    }

    func load() async {
        loadState = .loading
        notificationAuthorization = await notificationService.authorizationStatus()
        loadState = .loaded
    }

    func requestNotifications() async {
        notificationAuthorization = (try? await notificationService.requestAuthorization()) ?? .denied
        guard notificationAuthorization == .authorized else { return }
        let spaceID = sessionStore.currentSpace?.id
        let tasks = (try? await itemRepository.fetchItems(spaceID: spaceID)) ?? []
        let projects = (try? await projectRepository.fetchProjects(spaceID: spaceID)) ?? []
        await reminderScheduler.resync(tasks: tasks, projects: projects)
    }

    func createInvite() async {
        guard let inviterID = currentUser?.id else { return }
        _ = try? await relationshipService.createInvite(from: inviterID)
    }

    func updateTaskUrgencyWindow(minutes: Int) {
        guard var user = sessionStore.currentUser else { return }
        user.preferences.taskUrgencyWindowMinutes = minutes
        user.updatedAt = .now
        sessionStore.currentUser = user
    }

    func updateQuickTimePreset(minutes: Int, at index: Int) {
        guard var user = sessionStore.currentUser else { return }

        var presets = quickTimePresetMinutes
        guard presets.indices.contains(index) else { return }

        let roundedMinutes = NotificationSettings.normalizedQuickTimePresetMinutes([minutes]).first ?? minutes
        presets[index] = roundedMinutes
        user.preferences.quickTimePresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(presets)
        user.updatedAt = .now
        sessionStore.currentUser = user
    }

    func signOut() async {
        await authService.signOut()
        sessionStore.authState = .signedOut
        sessionStore.bindingState = .singleTrial
        sessionStore.currentUser = nil
        sessionStore.currentSpace = nil
        sessionStore.availableSpaces = []
        sessionStore.currentPairSpace = nil
    }
}
