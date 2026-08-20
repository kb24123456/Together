import SwiftUI

/// Compact editing content hosted by the root creation surface.
struct PeriodicTaskCreationCard: View {
    @Bindable var viewModel: RoutinesViewModel
    let session: PeriodicTaskCreationSession
    let isInteractive: Bool
    let onDiscard: () -> Void
    let onCommit: @MainActor () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var notes: String
    @State private var showsNotesEditor: Bool

    private enum Field: Hashable { case title, notes }

    init(
        viewModel: RoutinesViewModel,
        session: PeriodicTaskCreationSession,
        isInteractive: Bool,
        onDiscard: @escaping () -> Void,
        onCommit: @escaping @MainActor () async -> Void
    ) {
        self.viewModel = viewModel
        self.session = session
        self.isInteractive = isInteractive
        self.onDiscard = onDiscard
        self.onCommit = onCommit
        let initialNotes = session.draft.notes ?? ""
        _title = State(initialValue: session.draft.title)
        _notes = State(initialValue: initialNotes)
        _showsNotesEditor = State(initialValue: initialNotes.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
            titleRow
            notesSection
                .transition(disclosureTransition)

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.leading, 56)
                    .transition(disclosureTransition)
            }

            attributeBar
                .padding(.top, AppTheme.spacing.xxs)
        }
        .contentShape(Rectangle())
        .onTapGesture { }
        .onAppear { updateFocus(isInteractive) }
        .onChange(of: isInteractive) { _, value in updateFocus(value) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新建定期任务")
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppTheme.colors.body.opacity(0.30), lineWidth: 1.2)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            TextField("定期任务标题", text: $title, axis: .vertical)
                .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
                .lineLimit(1...3)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit(confirmTitleAfterSnapshot)
                .onChange(of: title) { _, value in
                    viewModel.updateCreationDraft { $0.title = value }
                }

            if focusedField == .title {
                Button("确认", action: confirmTitleAfterSnapshot)
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.sky)
                    .frame(minWidth: 44, minHeight: 40)
                    .buttonStyle(.plain)
            } else {
                Button(role: .cancel) {
                    focusedField = nil
                    onDiscard()
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.56))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("放弃新建定期任务")
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if showsNotesEditor {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                Color.clear.frame(width: 40, height: 36)

                TextField("添加备注", text: $notes, axis: .vertical)
                    .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .notes)
                    .submitLabel(.done)
                    .onSubmit(confirmNotesAfterSnapshot)
                    .onChange(of: notes) { _, value in updateNotes(value) }

                if focusedField == .notes {
                    Button("确认", action: confirmNotesAfterSnapshot)
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.sky)
                        .frame(minWidth: 44, minHeight: 36)
                        .buttonStyle(.plain)
                }
            }
        } else {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                Image(systemName: "plus")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.42))
                    .frame(width: 40, height: 36, alignment: .trailing)

                Button {
                    showsNotesEditor = true
                    Task { @MainActor in
                        await Task.yield()
                        focusedField = .notes
                    }
                } label: {
                    Text("添加备注")
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.48))
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var attributeBar: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            TaskAttributeToolbarRail {
                cycleMenu
                targetDayControl
                InlineTimePickerControl(
                    selection: currentRule?.hasTargetTime == true ? timeDate : nil,
                    fallbackSelection: .now,
                    onWillPresent: { focusedField = nil },
                    onCommit: updateTargetTime
                )
                reminderMenu
            }

            Button(action: commitCard) {
                Group {
                    if session.phase == .committing || session.phase == .committed {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                            .font(AppTheme.typography.sized(16, weight: .bold))
                    }
                }
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppTheme.colors.title))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(TaskMorphAttributeButtonStyle())
            .disabled(canAttemptCommit == false || session.phase != .editing)
            .opacity(canAttemptCommit ? 1 : 0.38)
            .accessibilityLabel("添加定期任务")
        }
    }

    private var cycleMenu: some View {
        Menu {
            ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                Button {
                    updateCycle(cycle)
                } label: {
                    if draftCycle == cycle {
                        Label(cycle.title, systemImage: "checkmark")
                    } else {
                        Text(cycle.title)
                    }
                }
            }
        } label: {
            attributeLabel(
                icon: "arrow.triangle.2.circlepath",
                title: draftCycle.title,
                isConfigured: true
            )
        }
        .buttonStyle(TaskMorphAttributeButtonStyle())
        .accessibilityLabel("定期任务维度，当前为\(draftCycle.title)")
    }

    @ViewBuilder
    private var targetDayControl: some View {
        if draftCycle == .daily {
            attributeLabel(icon: "calendar", title: "每天", isConfigured: true)
        } else {
            Menu {
                targetDayOptions(for: draftCycle)
                if currentRule?.hasTargetDay == true {
                    Divider()
                    Button("清除目标日", role: .destructive) {
                        mutateRule { $0.timing = nil }
                    }
                }
            } label: {
                attributeLabel(
                    icon: "calendar",
                    title: targetDayTitle,
                    isConfigured: currentRule?.hasTargetDay == true
                )
            }
            .buttonStyle(TaskMorphAttributeButtonStyle())
            .accessibilityLabel("目标日期，当前为\(targetDayTitle)")
        }
    }

    private var reminderMenu: some View {
        Menu {
            Button {
                updateReminder(leadMinutes: nil)
            } label: {
                if currentRule?.hasReminder == true {
                    Text("关闭提醒")
                } else {
                    Label("关闭提醒", systemImage: "checkmark")
                }
            }

            Divider()
            reminderOption("目标时刻", minutes: 0)
            reminderOption("提前 5 分钟", minutes: 5)
            reminderOption("提前 15 分钟", minutes: 15)
            reminderOption("提前 30 分钟", minutes: 30)
            reminderOption("提前 1 小时", minutes: 60)
            reminderOption("提前 1 天", minutes: 1_440)

            if currentRule?.hasReminder == true {
                Divider()
                Button {
                    updateReminderDelivery(.notification)
                } label: {
                    Label(
                        "普通通知",
                        systemImage: currentRule?.reminderDelivery == .alarm ? "bell" : "checkmark"
                    )
                }
                Button {
                    updateReminderDelivery(.alarm)
                } label: {
                    Label(
                        "原生闹钟",
                        systemImage: currentRule?.reminderDelivery == .alarm ? "checkmark" : "alarm"
                    )
                }
            }
        } label: {
            attributeLabel(
                icon: currentRule?.reminderDelivery == .alarm ? "alarm" : "bell",
                title: reminderTitle,
                isConfigured: currentRule?.hasReminder == true
            )
        }
        .buttonStyle(TaskMorphAttributeButtonStyle())
        .disabled(currentRule?.hasCompleteTarget(for: draftCycle) != true)
        .accessibilityLabel("定期任务提醒，当前为\(reminderTitle)")
    }

    private func attributeLabel(icon: String, title: String, isConfigured: Bool) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: isConfigured,
            usesContinuousCapsule: true,
            horizontalPadding: 8
        )
    }

    @ViewBuilder
    private func targetDayOptions(for cycle: PeriodicCycle) -> some View {
        switch cycle {
        case .daily:
            targetDayOption("每天", timing: .dayOfPeriod(1))
        case .weekly:
            ForEach(1...7, id: \.self) { day in
                targetDayOption(
                    RoutineTargetText.weekdayText(for: day),
                    timing: .dayOfPeriod(day)
                )
            }
        case .monthly:
            ForEach([1, 5, 10, 15, 20, 25, 31], id: \.self) { day in
                targetDayOption(
                    day == 31 ? "最后一天" : "\(day) 号",
                    timing: .dayOfPeriod(day)
                )
            }
        case .quarterly:
            targetDayOption("第 1 天", timing: .dayOfPeriod(1))
            targetDayOption("第 30 天", timing: .dayOfPeriod(30))
            targetDayOption("结束前 14 天", timing: .daysBeforeEnd(14))
        case .yearly:
            targetDayOption("第 1 天", timing: .dayOfPeriod(1))
            targetDayOption("第 180 天", timing: .dayOfPeriod(180))
            targetDayOption("结束前 30 天", timing: .daysBeforeEnd(30))
        }
    }

    private func targetDayOption(
        _ title: String,
        timing: PeriodicReminderRule.Timing
    ) -> some View {
        Button {
            mutateRule { $0.timing = timing }
        } label: {
            if currentRule?.timing == timing {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func reminderOption(_ title: String, minutes: Int) -> some View {
        Button {
            updateReminder(leadMinutes: minutes)
        } label: {
            if currentRule?.reminderLeadMinutes == minutes {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var draftCycle: PeriodicCycle {
        viewModel.creationSession?.draft.cycle ?? session.draft.cycle
    }

    private var currentRule: PeriodicReminderRule? {
        viewModel.creationSession?.draft.reminderRules.first
            ?? session.draft.reminderRules.first
    }

    private var targetDayTitle: String {
        guard let timing = currentRule?.timing else { return "目标日" }
        switch draftCycle {
        case .daily:
            return "每天"
        case .weekly:
            if case .dayOfPeriod(let day) = timing {
                return RoutineTargetText.weekdayText(for: day)
            }
            return "目标日"
        case .monthly:
            switch timing {
            case .dayOfPeriod(let day) where day >= 31: return "最后一天"
            case .dayOfPeriod(let day): return "\(day)号"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            }
        case .quarterly, .yearly:
            switch timing {
            case .dayOfPeriod(let day): return "第\(day)天"
            case .businessDayOfPeriod(let day): return "第\(day)工作日"
            case .daysBeforeEnd(let days): return "提前\(days)天"
            }
        }
    }

    private var reminderTitle: String {
        guard let rule = currentRule, rule.hasReminder else { return "提醒" }
        if rule.reminderDelivery == .alarm { return "闹钟" }
        guard let minutes = rule.reminderLeadMinutes else { return "提醒" }
        switch minutes {
        case 0: return "准时"
        case 5: return "提前5分"
        case 15: return "提前15分"
        case 30: return "提前30分"
        case 60: return "提前1时"
        case 1_440: return "提前1天"
        default: return "提醒"
        }
    }

    private var timeDate: Date {
        Calendar.current.date(
            from: DateComponents(hour: currentRule?.hour, minute: currentRule?.minute)
        ) ?? .now
    }

    private var canAttemptCommit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || focusedField == .title
    }

    private var disclosureTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.04)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    private func updateFocus(_ shouldFocus: Bool) {
        if shouldFocus {
            Task { @MainActor in
                await Task.yield()
                focusedField = .title
            }
        } else {
            focusedField = nil
        }
    }

    private func updateNotes(_ value: String) {
        viewModel.updateCreationDraft {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.notes = trimmed.isEmpty ? nil : value
        }
    }

    private func confirmTitleAfterSnapshot() {
        Task { @MainActor in
            title = TextInputSnapshotReader.resolvedText(fallback: title)
            viewModel.updateCreationDraft { $0.title = title }
            focusedField = nil
        }
    }

    private func confirmNotesAfterSnapshot() {
        Task { @MainActor in
            notes = TextInputSnapshotReader.resolvedText(fallback: notes)
            updateNotes(notes)
            focusedField = nil
        }
    }

    private func commitCard() {
        HomeInteractionFeedback.selection()
        Task { @MainActor in
            switch focusedField {
            case .title:
                title = TextInputSnapshotReader.resolvedText(fallback: title)
                viewModel.updateCreationDraft { $0.title = title }
            case .notes:
                notes = TextInputSnapshotReader.resolvedText(fallback: notes)
                updateNotes(notes)
            case nil:
                break
            }
            focusedField = nil
            await Task.yield()
            await onCommit()
        }
    }

    private func updateCycle(_ cycle: PeriodicCycle) {
        focusedField = nil
        viewModel.updateCreationDraft { draft in
            draft.cycle = cycle
            if let first = draft.reminderRules.first {
                let normalized = RoutinesViewModel.normalizedRule(first, for: cycle)
                draft.reminderRules = normalized.isEmpty ? [] : [normalized]
            }
        }
    }

    private func mutateRule(_ mutation: (inout PeriodicReminderRule) -> Void) {
        focusedField = nil
        viewModel.updateCreationDraft { draft in
            var rule = draft.reminderRules.first ?? RoutinesViewModel.defaultRule(for: draft.cycle)
            mutation(&rule)
            let normalized = RoutinesViewModel.normalizedRule(rule, for: draft.cycle)
            draft.reminderRules = normalized.isEmpty ? [] : [normalized]
        }
    }

    private func updateTargetTime(_ date: Date?) {
        mutateRule { rule in
            guard let date else {
                rule.hour = nil
                rule.minute = nil
                return
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            rule.hour = components.hour
            rule.minute = components.minute
        }
    }

    private func updateReminder(leadMinutes: Int?) {
        mutateRule { rule in
            rule.reminderLeadMinutes = leadMinutes
            if leadMinutes == nil {
                rule.reminderDelivery = nil
            } else if rule.reminderDelivery == nil {
                rule.reminderDelivery = .notification
            }
        }
    }

    private func updateReminderDelivery(_ delivery: PeriodicReminderDelivery) {
        Task { @MainActor in
            if delivery == .alarm {
                guard await viewModel.canUseAlarmDelivery() else { return }
            }
            mutateRule { rule in
                guard rule.reminderLeadMinutes != nil else { return }
                rule.reminderDelivery = delivery
            }
        }
    }
}
