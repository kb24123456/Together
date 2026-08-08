import SwiftUI

struct HomeInlineTaskDetailCard: View {
    let entry: HomeTimelineEntry
    @Bindable var viewModel: HomeViewModel

    @State private var newSubtaskTitle = ""
    @State private var schedulePresentation: ExistingTaskScheduleEditorPresentation?
    @FocusState private var isSubtaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.inlineDetailDraft?.subtasks ?? []) { subtask in
                HStack(spacing: 12) {
                    Button {
                        viewModel.toggleDetailDraftSubtask(subtask.id)
                    } label: {
                        Image(systemName: subtask.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundStyle(subtask.isCompleted ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.46))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    Text(subtask.title)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .strikethrough(subtask.isCompleted)
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.deleteDetailDraftSubtask(subtask.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除子任务")
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .foregroundStyle(AppTheme.colors.body.opacity(0.42))
                    .frame(width: 40, height: 40)
                TextField("添加子任务", text: $newSubtaskTitle)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                    .focused($isSubtaskFocused)
                    .submitLabel(.done)
                    .onSubmit(addSubtask)
                if newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Button("添加", action: addSubtask)
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                }
            }
            .frame(minHeight: 44)

            HStack(spacing: 4) {
                attributeButton(
                    title: dateTitle,
                    systemImage: "calendar",
                    isConfigured: viewModel.inlineDetailDraft?.dueAt != nil
                ) { openSchedule(.date) }
                attributeButton(
                    title: timeTitle,
                    systemImage: "clock",
                    isConfigured: viewModel.inlineDetailDraft?.hasExplicitTime == true
                ) { openSchedule(.time) }
                Menu {
                    Button("不提醒") { viewModel.setDraftReminderEnabled(false) }
                    if viewModel.inlineDetailDraft?.hasExplicitTime == true,
                       let dueAt = viewModel.inlineDetailDraft?.dueAt {
                        ForEach(TaskEditorReminderPreset.allCases) { preset in
                            Button(preset.title) {
                                viewModel.updateDraftReminder(dueAt.addingTimeInterval(-preset.secondsBeforeTarget))
                            }
                        }
                    }
                } label: {
                    TaskAttributeLabel(
                        icon: "bell",
                        title: viewModel.inlineDetailDraft?.remindAt == nil ? "" : "提醒",
                        isConfigured: viewModel.inlineDetailDraft?.remindAt != nil
                    )
                }
                Button {
                    viewModel.updateDraftUrgent(!(viewModel.inlineDetailDraft?.isUrgent ?? false))
                } label: {
                    TaskAttributeLabel(
                        icon: viewModel.inlineDetailDraft?.isUrgent == true ? "flag.fill" : "flag",
                        title: "",
                        isConfigured: viewModel.inlineDetailDraft?.isUrgent == true,
                        tint: viewModel.inlineDetailDraft?.isUrgent == true ? AppTheme.colors.coral : nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .sheet(item: $schedulePresentation) { presentation in
            ExistingTaskDateTimeEditorSheet(
                presentation: presentation,
                selectionFeedback: HomeInteractionFeedback.selection,
                onChange: { draft in
                    viewModel.updateDraftSchedule(date: draft.selectedDate, time: draft.selectedTime)
                }
            )
        }
    }

    private func attributeButton(
        title: String,
        systemImage: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TaskAttributeLabel(icon: systemImage, title: title, isConfigured: isConfigured)
        }
        .buttonStyle(.plain)
    }

    private var dateTitle: String {
        guard let date = viewModel.inlineDetailDraft?.dueAt else { return "日期" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        return date.formatted(.dateTime.month().day())
    }

    private var timeTitle: String {
        guard viewModel.inlineDetailDraft?.hasExplicitTime == true,
              let date = viewModel.inlineDetailDraft?.dueAt else { return "" }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func openSchedule(_ section: ExistingTaskScheduleEditorSection) {
        let draft = viewModel.inlineDetailDraft
        schedulePresentation = ExistingTaskScheduleEditorPresentation(
            initialSection: section,
            dueAt: draft?.dueAt,
            hasExplicitTime: draft?.hasExplicitTime ?? false,
            fallbackDate: viewModel.selectedDate
        )
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        viewModel.addDetailDraftSubtask(title: trimmed)
        newSubtaskTitle = ""
        isSubtaskFocused = true
    }
}
