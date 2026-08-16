import ActivityKit
import Foundation
import os

nonisolated enum TaskFollowReconcileReason: Sendable {
    case userMutation
    case dataChanged
    case appActive
    case authorizationChanged

    var allowsCreation: Bool {
        switch self {
        case .userMutation, .authorizationChanged:
            true
        case .dataChanged, .appActive:
            false
        }
    }
}

nonisolated enum TaskFollowReconcileResult: Equatable, Sendable {
    case synchronized
    case noActivity
    case activitiesDisabled
    case failed(String)
}

nonisolated enum TaskFollowSnapshotBuilder {
    static let maximumVisibleTaskCount = 3
    static let titleCharacterLimit = 80

    static func contentState(from tasks: [Item]) -> TaskFollowActivityAttributes.ContentState {
        let followedTasks = tasks
            .filter { item in
                item.repeatRule == nil
                    && item.isFollowed
                    && item.isArchived == false
                    && item.status != .completed
                    && item.completedAt == nil
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.followedAt ?? .distantPast
                let rhsDate = rhs.followedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let visibleTasks = followedTasks.prefix(maximumVisibleTaskCount).map { item in
            FollowedTaskSnapshot(
                taskID: item.id,
                displayTitle: normalizedTitle(item.title),
                dueAt: item.dueAt,
                hasExplicitTime: item.hasExplicitTime
            )
        }
        return TaskFollowActivityAttributes.ContentState(
            visibleTasks: Array(visibleTasks),
            totalFollowedCount: followedTasks.count
        )
    }

    private static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "未命名待办" : trimmed
        return String(fallback.prefix(titleCharacterLimit))
    }
}

actor TaskFollowActivityCoordinator {
    private typealias FollowActivity = Activity<TaskFollowActivityAttributes>

    private let itemRepository: ItemRepositoryProtocol
    private let authorizationDefaults: UserDefaults
    private let authorizationDefaultsKey = "taskFollow.lastKnownActivitiesEnabled"
    private let logger = Logger(
        subsystem: "com.pigdog.Together",
        category: "TaskFollowActivity"
    )

    init(
        itemRepository: ItemRepositoryProtocol,
        authorizationDefaults: UserDefaults = .standard
    ) {
        self.itemRepository = itemRepository
        self.authorizationDefaults = authorizationDefaults
    }

    func reconcile(
        spaceID: UUID,
        reason: TaskFollowReconcileReason
    ) async -> TaskFollowReconcileResult {
        do {
            let tasks = try await itemRepository.fetchActiveItems(spaceID: spaceID)
            let state = TaskFollowSnapshotBuilder.contentState(from: tasks)
            let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            authorizationDefaults.set(activitiesEnabled, forKey: authorizationDefaultsKey)

            let activities = FollowActivity.activities
            if state.totalFollowedCount == 0 {
                for activity in activities {
                    await activity.end(
                        ActivityContent(state: state, staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                }
                return .synchronized
            }

            guard activitiesEnabled else { return .activitiesDisabled }

            let activeActivities = activities.filter { $0.activityState == .active }
            for inactive in activities where inactive.activityState != .active {
                await inactive.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }

            if let keeper = activeActivities.first {
                for duplicate in activeActivities.dropFirst() {
                    await duplicate.end(
                        ActivityContent(state: state, staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                }
                await keeper.update(ActivityContent(state: state, staleDate: nil))
                return .synchronized
            }

            guard reason.allowsCreation else { return .noActivity }

            _ = try FollowActivity.request(
                attributes: TaskFollowActivityAttributes(sessionID: UUID()),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            return .synchronized
        } catch {
            logger.error("reconcile failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    func reconcileAfterAppBecameActive(spaceID: UUID) async -> TaskFollowReconcileResult {
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let previousValue = authorizationDefaults.object(forKey: authorizationDefaultsKey) as? Bool
        let reason: TaskFollowReconcileReason = previousValue == false && activitiesEnabled
            ? .authorizationChanged
            : .appActive
        return await reconcile(spaceID: spaceID, reason: reason)
    }
}
