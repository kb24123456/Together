import SwiftUI

enum TaskDetailRoute: Hashable {
    case todo(UUID)
    case periodic(UUID)

    var id: UUID {
        switch self {
        case .todo(let id), .periodic(let id):
            id
        }
    }

    var domain: TaskMorphDomain {
        switch self {
        case .todo:
            .todo
        case .periodic:
            .periodic
        }
    }
}

extension View {
    @ViewBuilder
    func taskDetailMatchedTransitionSource(
        _ route: TaskDetailRoute,
        in namespace: Namespace.ID?,
        isEnabled: Bool
    ) -> some View {
        if isEnabled, let namespace {
            matchedTransitionSource(id: route, in: namespace)
        } else {
            self
        }
    }
}

struct TaskDetailPresentation: Identifiable, Hashable {
    let id: UUID
    let route: TaskDetailRoute

    init(
        id: UUID = UUID(),
        route: TaskDetailRoute
    ) {
        self.id = id
        self.route = route
    }

    func canReleaseSharedDraft(while activePresentation: TaskDetailPresentation?) -> Bool {
        activePresentation == nil || activePresentation?.id == id
    }
}

struct TaskDetailView: View {
    let presentation: TaskDetailPresentation
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var routinesViewModel: RoutinesViewModel
    let onDidDisappear: @MainActor (TaskDetailPresentation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isClosing = false
    @State private var didStartDisappearanceCleanup = false
    @State private var inputCommitRequestRevision: UInt = 0
    @State private var hasTransientInputChanges = false

    private var route: TaskDetailRoute {
        presentation.route
    }

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .todo(let id):
                    todoDetail(id: id)
                case .periodic(let id):
                    periodicDetail(id: id)
                }
            }
            .background(AppTheme.colors.background.ignoresSafeArea())
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", action: cancelAndClose)
                        .labelStyle(.iconOnly)
                        .disabled(isClosing)
                        .accessibilityHint("放弃尚未确认的更改")
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isClosing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在保存任务")
                    } else {
                        Button("确认", systemImage: "checkmark") {
                            Task { await saveAndClose() }
                        }
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                        .disabled(hasUnsavedChanges == false)
                        .accessibilityHint(
                            hasUnsavedChanges
                                ? "保存更改并关闭任务详情"
                                : "任务内容尚未更改"
                        )
                    }
                }
            }
        }
        .interactiveDismissDisabled(isClosing)
        .accessibilityAction(.escape) {
            cancelAndClose()
        }
        .onDisappear {
            guard didStartDisappearanceCleanup == false else { return }
            didStartDisappearanceCleanup = true
            onDidDisappear(presentation)
        }
    }

    @ViewBuilder
    private func todoDetail(id: UUID) -> some View {
        if let entry = homeViewModel.timelineEntry(for: id),
           let draft = homeViewModel.detailDraft {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeTimelineRow(
                        entry: entry,
                        isAnimatingCompletion: false,
                        isAnimatingReopening: false,
                        isDetailPresented: true,
                        isDetailExpanded: true,
                        isUrgent: draft.isUrgent,
                        isFollowed: homeViewModel.item(for: id)?.isFollowed == true,
                        expandedTitle: draft.title,
                        expandedNotes: draft.notes,
                        isEditingNotes: false,
                        motion: .navigationDetail,
                        requestsInitialTitleFocus: true,
                        inputCommitRequestRevision: inputCommitRequestRevision,
                        onToggleCompletion: {
                            Task { await completeAndClose() }
                        },
                        onOpenDetail: {},
                        onUpdateTitle: homeViewModel.updateDraftTitle,
                        onUpdateNotes: homeViewModel.updateDraftNotes,
                        onBeginNoteEditing: {},
                        onEndNoteEditing: {},
                        onInlineFocus: { _ in }
                    )

                    HomeInlineTaskDetailCard(
                        entry: entry,
                        viewModel: homeViewModel,
                        isExpanded: true,
                        isCollapsing: false,
                        cascadeElapsed: TaskMorphCascadeTiming.timelineDuration,
                        cascadeRowCount: todoCascadeRowCount,
                        usesGlobalConfirmation: true,
                        inputCommitRequestRevision: inputCommitRequestRevision,
                        onTransientInputChange: { hasTransientInputChanges = $0 }
                    )

                    detailError
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.md)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom, alignment: .leading, spacing: 0) {
                HomeTaskAttributeFooter(
                    entry: entry,
                    viewModel: homeViewModel,
                    isExpanded: isClosing == false
                )
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.xs)
                .padding(.bottom, AppTheme.spacing.sm)
            }
        } else {
            unavailableDetail
        }
    }

    @ViewBuilder
    private func periodicDetail(id: UUID) -> some View {
        if let task = routinesViewModel.tasks.first(where: { $0.id == id }),
           routinesViewModel.detailDraft != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RoutinesTaskRow(
                        task: task,
                        viewModel: routinesViewModel,
                        isAnimatingCompletion: false,
                        isAnimatingReopening: false,
                        isDetailPresented: true,
                        isDetailExpanded: true,
                        isDetailCollapsing: false,
                        expansionMotion: .navigationDetail,
                        cascadeRowCount: 1,
                        requestsInitialTitleFocus: true,
                        showsAttributeToolbar: false,
                        inputCommitRequestRevision: inputCommitRequestRevision,
                        onOpenDetail: {},
                        onToggleCompletion: {
                            Task { await completeAndClose() }
                        },
                        onDismissDetail: {
                            Task { await saveAndClose() }
                        },
                        onInlineFocus: { _ in }
                    )

                    detailError
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.md)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom, alignment: .leading, spacing: 0) {
                PeriodicTaskAttributeFooter(
                    task: task,
                    viewModel: routinesViewModel,
                    isExpanded: isClosing == false
                )
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.xs)
                .padding(.bottom, AppTheme.spacing.sm)
            }
        } else {
            unavailableDetail
        }
    }

    @ViewBuilder
    private var detailError: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(AppTheme.typography.scaled(13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(AppTheme.colors.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppTheme.spacing.sm)
        }
    }

    private var unavailableDetail: some View {
        ContentUnavailableView(
            "无法打开任务",
            systemImage: "exclamationmark.triangle",
            description: Text("任务可能已被删除或移动，请返回列表刷新后重试。")
        )
    }

    private var todoCascadeRowCount: Int {
        (homeViewModel.detailDraft?.subtasks.count ?? 0) + 3
    }

    private var hasUnsavedChanges: Bool {
        if hasTransientInputChanges { return true }

        return switch route {
        case .todo:
            homeViewModel.hasUnsavedDetailChanges
        case .periodic(let id):
            routinesViewModel.tasks
                .first(where: { $0.id == id })
                .map(routinesViewModel.hasUnsavedInlineChanges(for:))
                ?? false
        }
    }

    private func cancelAndClose() {
        guard isClosing == false else { return }
        isClosing = true
        errorMessage = nil
        dismiss()
    }

    @MainActor
    private func saveAndClose() async {
        guard isClosing == false else { return }
        isClosing = true
        errorMessage = nil

        guard isCurrentDetailAvailable else {
            dismiss()
            return
        }

        inputCommitRequestRevision &+= 1
        await Task.yield()
        await Task.yield()

        guard await persistCurrentDetail() else {
            isClosing = false
            return
        }

        dismiss()
    }

    private var isCurrentDetailAvailable: Bool {
        switch route {
        case .todo(let id):
            homeViewModel.timelineEntry(for: id) != nil && homeViewModel.detailDraft != nil
        case .periodic(let id):
            routinesViewModel.tasks.contains(where: { $0.id == id })
                && routinesViewModel.detailDraft != nil
        }
    }

    @MainActor
    private func completeAndClose() async {
        guard isClosing == false else { return }
        isClosing = true
        errorMessage = nil

        await Task.yield()
        await Task.yield()

        guard await persistCurrentDetail() else {
            isClosing = false
            return
        }

        let didComplete: Bool
        switch route {
        case .todo(let id):
            homeViewModel.dismissOperationError()
            await homeViewModel.completeItem(id, trigger: .taskExpansion)
            didComplete = homeViewModel.item(for: id)?.status == .completed
            if didComplete == false {
                errorMessage = homeViewModel.operationErrorMessage ?? "任务状态更新失败，请重试。"
            }
        case .periodic(let id):
            routinesViewModel.dismissOperationError()
            await routinesViewModel.toggleCompletion(taskID: id)
            if let task = routinesViewModel.tasks.first(where: { $0.id == id }) {
                didComplete = routinesViewModel.isCompleted(task)
            } else {
                didComplete = false
            }
            if didComplete == false {
                errorMessage = routinesViewModel.operationErrorMessage ?? "定期任务状态更新失败，请重试。"
            }
        }

        guard didComplete else {
            isClosing = false
            return
        }

        dismiss()
    }

    @MainActor
    private func persistCurrentDetail() async -> Bool {
        switch route {
        case .todo:
            let didSave = await homeViewModel.saveInlineDetailDraft()
            if didSave == false {
                errorMessage = homeViewModel.operationErrorMessage ?? "任务保存失败，请重试。"
            }
            return didSave
        case .periodic:
            let didSave = await routinesViewModel.saveInlineDetailDraft()
            if didSave == false {
                errorMessage = routinesViewModel.operationErrorMessage ?? "定期任务保存失败，请重试。"
            }
            return didSave
        }
    }

}
