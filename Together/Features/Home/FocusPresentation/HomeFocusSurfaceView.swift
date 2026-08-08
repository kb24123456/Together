import SwiftUI

struct HomeFocusSurfaceView: View {
    @Environment(AppContext.self) private var appContext
    @Bindable var focusModel: HomeFocusPresentationModel

    var body: some View {
        Group {
            if let subject = focusModel.subject {
                surface(for: subject)
            } else {
                Color.clear
            }
        }
        .background(AppTheme.colors.surface)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) {
            focusModel.requestDismissal()
        }
    }

    @ViewBuilder
    private func surface(for subject: HomeFocusSubject) -> some View {
        switch subject {
        case .detail(.todo, let itemID):
            todoDetail(itemID: itemID)
        case .creation(.todo, let sessionID):
            todoCreation(sessionID: sessionID)
        case .detail(.periodic, let itemID):
            periodicDetail(itemID: itemID)
        case .creation(.periodic, let sessionID):
            periodicCreation(sessionID: sessionID)
        }
    }

    @ViewBuilder
    private func todoDetail(itemID: UUID) -> some View {
        let viewModel = appContext.homeViewModel
        if let entry = viewModel.timelineEntry(for: itemID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeTimelineRow(
                        entry: entry,
                        isAnimatingCompletion: false,
                        isAnimatingReopening: false,
                        titleLineLimit: 3,
                        titleMinimumScaleFactor: 0.8,
                        isDetailPresented: true,
                        isDetailExpanded: true,
                        isUrgent: viewModel.inlineDetailDraft?.isUrgent ?? entry.isUrgent,
                        expandedTitle: viewModel.inlineDetailDraft?.title ?? entry.title,
                        expandedNotes: viewModel.inlineDetailDraft?.notes ?? entry.notes,
                        isEditingNotes: false,
                        onToggleCompletion: { focusModel.requestCompletion() },
                        onOpenDetail: {},
                        onUpdateTitle: viewModel.updateDraftTitle,
                        onUpdateNotes: viewModel.updateDraftNotes,
                        onBeginNoteEditing: {},
                        onEndNoteEditing: {},
                        onInlineFocus: { _ in }
                    )
                    HomeInlineTaskDetailCard(entry: entry, viewModel: viewModel)
                        .padding(.leading, 52)
                }
                .padding(
                    EdgeInsets(
                        top: 14,
                        leading: AppTheme.spacing.xl,
                        bottom: AppTheme.spacing.lg,
                        trailing: AppTheme.spacing.xl
                    )
                )
            }
            .scrollIndicators(.hidden)
        } else {
            unavailableSurface
        }
    }

    @ViewBuilder
    private func todoCreation(sessionID: UUID) -> some View {
        let viewModel = appContext.homeViewModel
        if let session = viewModel.taskCreationSession, session.id == sessionID {
            ScrollView {
                HomeTaskCreationCard(
                    viewModel: viewModel,
                    session: session,
                    isExpanded: true,
                    isInteractive: focusModel.isInteractive,
                    onDiscard: { focusModel.requestDismissal() },
                    onCommit: commitTodoCreation
                )
            }
            .scrollIndicators(.hidden)
        } else {
            unavailableSurface
        }
    }

    @ViewBuilder
    private func periodicDetail(itemID: UUID) -> some View {
        let viewModel = appContext.routinesViewModel
        if let task = viewModel.tasks.first(where: { $0.id == itemID }) {
            ScrollView {
                RoutinesTaskRow(
                    task: task,
                    viewModel: viewModel,
                    isAnimatingCompletion: false,
                    isAnimatingReopening: false,
                    isDetailPresented: true,
                    isDetailExpanded: true,
                    animationBatch: 0,
                    onOpenDetail: {},
                    onToggleCompletion: { focusModel.requestCompletion() },
                    onInlineFocus: { _ in }
                )
                .padding(
                    EdgeInsets(
                        top: 24,
                        leading: AppTheme.spacing.xl,
                        bottom: AppTheme.spacing.lg,
                        trailing: AppTheme.spacing.xl
                    )
                )
            }
            .scrollIndicators(.hidden)
        } else {
            unavailableSurface
        }
    }

    @ViewBuilder
    private func periodicCreation(sessionID: UUID) -> some View {
        let viewModel = appContext.routinesViewModel
        if let session = viewModel.creationSession, session.id == sessionID {
            ScrollView {
                PeriodicTaskCreationCard(
                    viewModel: viewModel,
                    session: session,
                    isInteractive: focusModel.isInteractive,
                    onDiscard: { focusModel.requestDismissal() },
                    onCommit: commitPeriodicCreation
                )
            }
            .scrollIndicators(.hidden)
        } else {
            unavailableSurface
        }
    }

    private var unavailableSurface: some View {
        ContentUnavailableView("任务不可用", systemImage: "exclamationmark.triangle")
    }

    private func commitTodoCreation() async {
        guard let token = focusModel.beginSaving() else { return }
        let result = await appContext.homeViewModel.commitTaskCreationForFocus()
        focusModel.finishSaving(using: token, result: result)
    }

    private func commitPeriodicCreation() async {
        guard let token = focusModel.beginSaving() else { return }
        let result = await appContext.routinesViewModel.commitFocusCreation()
        if case .saved(let descriptor) = result,
           case .periodic(let cycle) = descriptor.section {
            appContext.routinesViewModel.selectCycle(cycle)
        }
        focusModel.finishSaving(using: token, result: result)
    }
}
