import SwiftUI

struct HomeTaskCreationCard: View {
    @Bindable var viewModel: HomeViewModel
    let session: HomeTaskCreationSession
    let isExpanded: Bool
    let isInteractive: Bool
    let onDiscard: () -> Void
    let onCommit: @MainActor () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var notes: String
    @State private var newSubtaskTitle = ""
    @State private var activePanel: Panel?

    private enum Field: Hashable { case title, notes, subtask }
    private enum Panel: String, Identifiable { case date, time, reminder; var id: String { rawValue } }

    init(
        viewModel: HomeViewModel,
        session: HomeTaskCreationSession,
        isExpanded: Bool = true,
        isInteractive: Bool = true,
        onDiscard: @escaping () -> Void = {},
        onCommit: @escaping @MainActor () async -> Void = {}
    ) {
        self.viewModel = viewModel
        self.session = session
        self.isExpanded = isExpanded
        self.isInteractive = isInteractive
        self.onDiscard = onDiscard
        self.onCommit = onCommit
        _title = State(initialValue: session.draft.title)
        _notes = State(initialValue: session.draft.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                    .strokeBorder(AppTheme.colors.body.opacity(0.38), style: StrokeStyle(lineWidth: 1.6, dash: [3.6, 4.4]))
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("任务标题", text: $title, axis: .vertical)
                        .font(AppTheme.typography.sized(20, weight: .bold))
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                        .onChange(of: title) { _, value in
                            viewModel.updateTaskCreationDraft { $0.title = value }
                        }

                    TextField("添加备注", text: $notes, axis: .vertical)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .notes)
                        .onChange(of: notes) { _, value in
                            viewModel.updateTaskCreationDraft {
                                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                $0.notes = trimmed.isEmpty ? nil : value
                            }
                        }
                }
            }

            if isExpanded {
                subtaskRows
                    .transition(disclosureTransition)
                attributeBar
                    .transition(disclosureTransition)
            }

            if isExpanded, let activePanel {
                panel(activePanel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isExpanded, let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(disclosureTransition)
            }

            if isExpanded {
                HStack(spacing: 12) {
                    Button("放弃", role: .cancel) {
                        focusedField = nil
                        onDiscard()
                    }
                    .frame(minWidth: 72, minHeight: 44)

                    Button {
                        focusedField = nil
                        Task { await onCommit() }
                    } label: {
                        Group {
                            if session.phase == .committing || session.phase == .committed {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("添加")
                            }
                        }
                        .font(AppTheme.typography.sized(15, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(AppTheme.colors.title))
                    }
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.phase != .editing)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                }
                .transition(disclosureTransition)
            }
        }
        .padding(
            EdgeInsets(
                top: 2,
                leading: 0,
                bottom: AppTheme.spacing.lg,
                trailing: 0
            )
        )
        .contentShape(Rectangle())
        .onTapGesture { }
        .onAppear {
            guard isExpanded, isInteractive else { return }
            Task { @MainActor in
                await Task.yield()
                focusedField = .title
            }
        }
        .onChange(of: isInteractive) { _, interactive in
            if interactive {
                Task { @MainActor in
                    await Task.yield()
                    focusedField = .title
                }
            } else {
                focusedField = nil
                activePanel = nil
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.28, extraBounce: 0), value: activePanel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新建待办")
    }

    private var disclosureTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.05)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    @ViewBuilder
    private var subtaskRows: some View {
        ForEach(session.draft.subtasks) { subtask in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(AppTheme.colors.body.opacity(0.32), style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
                    .frame(width: 28, height: 28)
                Text(subtask.title)
                    .font(AppTheme.typography.sized(15, weight: .medium))
                Spacer()
                Button(role: .destructive) {
                    viewModel.updateTaskCreationDraft { draft in
                        draft.subtasks.removeAll { $0.id == subtask.id }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除子任务")
            }
        }

        HStack(spacing: 10) {
            Image(systemName: "plus")
                .frame(width: 28, height: 28)
                .foregroundStyle(AppTheme.colors.body.opacity(0.48))
            TextField("添加子任务", text: $newSubtaskTitle)
                .font(AppTheme.typography.sized(15, weight: .medium))
                .focused($focusedField, equals: .subtask)
                .submitLabel(.done)
                .onSubmit(addSubtask)
            if newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Button("添加", action: addSubtask)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
            }
        }
        .frame(minHeight: 44)
    }

    private var attributeBar: some View {
        HStack(spacing: 4) {
            attributeButton(.date, title: dateText, systemImage: "calendar")
            attributeButton(.time, title: session.draft.hasExplicitTime ? timeText : nil, systemImage: "clock")
            attributeButton(.reminder, title: session.draft.remindAt == nil ? nil : "提醒", systemImage: "bell")
            Button {
                viewModel.updateTaskCreationDraft { $0.isUrgent.toggle() }
            } label: {
                Image(systemName: session.draft.isUrgent ? "flag.fill" : "flag")
                    .foregroundStyle(session.draft.isUrgent ? AppTheme.colors.coral : AppTheme.colors.body.opacity(0.64))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("紧急")
            .accessibilityValue(session.draft.isUrgent ? "已开启" : "已关闭")
        }
    }

    private func attributeButton(_ panel: Panel, title: String?, systemImage: String) -> some View {
        Button {
            focusedField = nil
            activePanel = activePanel == panel ? nil : panel
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                if let title { Text(title).lineLimit(1) }
            }
            .font(AppTheme.typography.sized(12, weight: .semibold))
            .foregroundStyle(activePanel == panel ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.64))
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(alignment: .bottom) {
                Capsule().fill(AppTheme.colors.sky).frame(width: 24, height: 3).opacity(activePanel == panel ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func panel(_ panel: Panel) -> some View {
        switch panel {
        case .date:
            DatePicker("日期", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        case .time:
            VStack(spacing: 8) {
                DatePicker("时间", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                if session.draft.hasExplicitTime {
                    Button("清除时间", role: .destructive) {
                        viewModel.updateTaskCreationDraft {
                            $0.hasExplicitTime = false
                            $0.remindAt = nil
                            $0.dueAt = Calendar.current.startOfDay(for: $0.dueAt ?? .now)
                        }
                        activePanel = nil
                    }
                }
            }
        case .reminder:
            if session.draft.hasExplicitTime, let dueAt = session.draft.dueAt {
                VStack(alignment: .leading, spacing: 4) {
                    Button("不提醒") { viewModel.updateTaskCreationDraft { $0.remindAt = nil } }
                    ForEach(TaskEditorReminderPreset.allCases) { preset in
                        Button(preset.title) {
                            viewModel.updateTaskCreationDraft {
                                $0.remindAt = dueAt.addingTimeInterval(-preset.secondsBeforeTarget)
                            }
                            activePanel = nil
                        }
                    }
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button("设置时间后可添加提醒") { activePanel = .time }
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { session.draft.dueAt ?? .now },
            set: { value in
                viewModel.updateTaskCreationDraft { draft in
                    let calendar = Calendar.current
                    if draft.hasExplicitTime, let old = draft.dueAt {
                        let time = calendar.dateComponents([.hour, .minute], from: old)
                        var date = calendar.dateComponents([.year, .month, .day], from: value)
                        date.hour = time.hour
                        date.minute = time.minute
                        draft.dueAt = calendar.date(from: date)
                    } else {
                        draft.dueAt = calendar.startOfDay(for: value)
                    }
                }
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { session.draft.dueAt ?? .now },
            set: { value in
                viewModel.updateTaskCreationDraft { draft in
                    let calendar = Calendar.current
                    let day = draft.dueAt ?? .now
                    var components = calendar.dateComponents([.year, .month, .day], from: day)
                    let time = calendar.dateComponents([.hour, .minute], from: value)
                    components.hour = time.hour
                    components.minute = (time.minute ?? 0) / 5 * 5
                    draft.dueAt = calendar.date(from: components)
                    draft.hasExplicitTime = true
                }
            }
        )
    }

    private var dateText: String {
        guard let date = session.draft.dueAt else { return "今天" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        return date.formatted(.dateTime.month().day())
    }

    private var timeText: String? {
        session.draft.dueAt?.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        viewModel.updateTaskCreationDraft { draft in
            draft.subtasks.append(TaskSubtaskDraft(title: trimmed, sortOrder: draft.subtasks.count))
        }
        newSubtaskTitle = ""
        focusedField = .subtask
    }
}
