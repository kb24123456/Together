import SwiftUI

struct HomeItemDetailSheet: View {
    @Bindable var viewModel: HomeViewModel
    @FocusState private var focusedField: Field?
    @State private var activeMenu: DetailMenu?

    private enum Field: Hashable {
        case title
        case notes
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.detailDraft != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            editorSection
                            chipSection
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 36)
                    }
                    .scrollIndicators(.hidden)
                    .background(.clear)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        HomeInteractionFeedback.selection()
                        viewModel.dismissItemDetail()
                    }
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                }
            }
        }
        .background(.clear)
        .sheet(item: $activeMenu) { menu in
            DetailMenuSheet(menu: menu, viewModel: viewModel)
                .presentationDetents(menu.detents)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
                .modifier(DetailMenuPresentationSizingModifier())
        }
        .presentationDetents([.medium, .large], selection: $viewModel.detailDetent)
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: focusedField) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.markDetailForExpandedEditing()
            }
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "任务标题",
                text: Binding(
                    get: { viewModel.detailDraft?.title ?? "" },
                    set: { viewModel.updateDraftTitle($0) }
                ),
                axis: .vertical
            )
            .font(AppTheme.typography.sized(34, weight: .bold))
            .foregroundStyle(AppTheme.colors.title)
            .focused($focusedField, equals: .title)

            TextField(
                "添加备注...",
                text: Binding(
                    get: { viewModel.detailDraft?.notes ?? "" },
                    set: { viewModel.updateDraftNotes($0) }
                ),
                axis: .vertical
            )
            .font(AppTheme.typography.sized(20, weight: .regular))
            .foregroundStyle(AppTheme.colors.body.opacity(0.88))
            .lineLimit(4, reservesSpace: true)
            .focused($focusedField, equals: .notes)
        }
    }

    private var chipSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                detailChip(systemImage: "calendar", title: dueDateTitle, menu: .date)
                detailChip(systemImage: "clock", title: dueTimeTitle, menu: .time)
                detailChip(systemImage: "bell", title: reminderTitle, menu: .reminder)
                detailChip(
                    systemImage: "flag",
                    title: viewModel.detailDraft?.priority.title ?? "普通",
                    menu: .priority
                )
                detailChip(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: repeatTitle,
                    menu: .repeatRule
                )
                pinChip
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func detailChip(systemImage: String, title: String, menu: DetailMenu) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            activeMenu = menu
        } label: {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                Text(title)
                    .font(AppTheme.typography.sized(14, weight: .semibold))
            }
            .foregroundStyle(AppTheme.colors.body.opacity(0.84))
            .padding(.horizontal, DetailChipMetrics.horizontalPadding)
            .padding(.vertical, DetailChipMetrics.verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.54), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var pinChip: some View {
        Button {
            HomeInteractionFeedback.selection()
            viewModel.updateDraftPinned(!(viewModel.detailDraft?.isPinned ?? false))
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "pin")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                Text((viewModel.detailDraft?.isPinned ?? false) ? "已置顶" : "置顶")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
            }
            .foregroundStyle(AppTheme.colors.body.opacity(0.84))
            .padding(.horizontal, DetailChipMetrics.horizontalPadding)
            .padding(.vertical, DetailChipMetrics.verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.54), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var dueDateTitle: String {
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "今天" }
        return dueAt.formatted(.dateTime.month().day())
    }

    private var dueTimeTitle: String {
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "时间" }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else {
            return remindAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        let delta = dueAt.timeIntervalSince(remindAt)
        if let preset = DetailReminderPreset.preset(for: delta) {
            return preset.chipTitle
        }
        return remindAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var repeatTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt)
    }
}

private struct DetailMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}

private enum DetailMenu: String, Identifiable {
    case date
    case time
    case reminder
    case priority
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.height(430)]
        case .time:
            return [.height(320)]
        case .reminder, .priority, .repeatRule:
            return [.medium]
        }
    }
}

private struct DetailMenuSheet: View {
    let menu: DetailMenu
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        menuContent
            .background(.clear)
    }

    @ViewBuilder
    private var menuContent: some View {
        switch menu {
        case .date:
            dateMenu
        case .time:
            timeMenu
        case .reminder:
            optionList(options: reminderOptions)
        case .priority:
            optionList(options: priorityOptions)
        case .repeatRule:
            optionList(options: repeatOptions)
        }
    }

    private var dateMenu: some View {
        VStack(spacing: 14) {
            DatePicker(
                "日期",
                selection: Binding(
                    get: { viewModel.detailDraft?.dueAt ?? .now },
                    set: { viewModel.updateDraftDueDate($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)

            Button {
                HomeInteractionFeedback.selection()
                viewModel.setDraftDueDateEnabled(false)
                dismiss()
            } label: {
                Text("清除日期")
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DetailMenuOptionMetrics.height)
            }
            .buttonStyle(DetailMenuOptionButtonStyle())
            .modifier(DetailMenuOptionGlassModifier())
        }
        .padding(DetailMenuOptionMetrics.outerInset)
    }

    private var timeMenu: some View {
        VStack(spacing: 14) {
            DatePicker(
                "时间",
                selection: Binding(
                    get: { viewModel.detailDraft?.dueAt ?? .now },
                    set: { newValue in
                        ensureDueDateExists()
                        viewModel.updateDraftDueTime(newValue)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()

            Button {
                HomeInteractionFeedback.selection()
                ensureDueDateExists()
                let fallbackTime = Calendar.current.date(
                    bySettingHour: 9,
                    minute: 0,
                    second: 0,
                    of: viewModel.detailDraft?.dueAt ?? .now
                ) ?? .now
                viewModel.updateDraftDueTime(fallbackTime)
                dismiss()
            } label: {
                Text("设为 09:00")
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DetailMenuOptionMetrics.height)
            }
            .buttonStyle(DetailMenuOptionButtonStyle())
            .modifier(DetailMenuOptionGlassModifier())
        }
        .padding(DetailMenuOptionMetrics.outerInset)
    }

    private var reminderOptions: [DetailMenuOption] {
        let currentTitle = reminderChipTitle
        return [DetailMenuOption(title: "不提醒", isSelected: viewModel.detailDraft?.remindAt == nil) {
            viewModel.setDraftReminderEnabled(false)
            dismiss()
        }] + DetailReminderPreset.allCases.map { preset in
            DetailMenuOption(
                title: preset.title,
                isSelected: currentTitle == preset.chipTitle
            ) {
                ensureDueDateExists()
                let dueAt = viewModel.detailDraft?.dueAt ?? .now
                viewModel.updateDraftReminder(dueAt.addingTimeInterval(-preset.secondsBeforeTarget))
                dismiss()
            }
        }
    }

    private var priorityOptions: [DetailMenuOption] {
        ItemPriority.allCases.map { priority in
            DetailMenuOption(title: priority.title, isSelected: viewModel.detailDraft?.priority == priority) {
                viewModel.updateDraftPriority(priority)
                dismiss()
            }
        }
    }

    private var repeatOptions: [DetailMenuOption] {
        let anchorDate = viewModel.detailDraft?.dueAt ?? .now
        let currentTitle = repeatChipTitle
        return [DetailMenuOption(title: "不重复", isSelected: viewModel.detailDraft?.repeatRule == nil) {
            viewModel.updateDraftRepeatRule(nil as ItemRepeatRule?)
            dismiss()
        }] + DetailRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: anchorDate)
            return DetailMenuOption(title: title, isSelected: currentTitle == title) {
                ensureDueDateExists()
                viewModel.updateDraftRepeatRule(preset.makeRule(anchorDate: anchorDate))
                dismiss()
            }
        }
    }

    private func optionList(options: [DetailMenuOption]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        HomeInteractionFeedback.selection()
                        option.action()
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(AppTheme.typography.sized(17, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            Spacer(minLength: 0)
                            if option.isSelected {
                                Image(systemName: "checkmark")
                                    .font(AppTheme.typography.sized(14, weight: .bold))
                                    .foregroundStyle(AppTheme.colors.coral)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: DetailMenuOptionMetrics.height)
                        .padding(.horizontal, 18)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: DetailMenuOptionMetrics.cornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(DetailMenuOptionButtonStyle())
                    .modifier(DetailMenuOptionGlassModifier())
                }
            }
            .padding(DetailMenuOptionMetrics.outerInset)
        }
        .scrollIndicators(.hidden)
        .background(.clear)
    }

    private var reminderChipTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "提醒" }
        let delta = dueAt.timeIntervalSince(remindAt)
        if let preset = DetailReminderPreset.preset(for: delta) {
            return preset.chipTitle
        }
        return "提醒"
    }

    private var repeatChipTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt)
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }
}

private struct DetailMenuOption: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private struct DetailChipMetrics {
    static let horizontalPadding: CGFloat = 13
    static let verticalPadding: CGFloat = 8
}

private struct DetailMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

private struct DetailMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: DetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: DetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: DetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private struct DetailMenuOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private enum DetailReminderPreset: CaseIterable, Identifiable {
    case atTime
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay

    var id: String { title }

    var secondsBeforeTarget: TimeInterval {
        switch self {
        case .atTime:
            return 0
        case .fiveMinutes:
            return 300
        case .fifteenMinutes:
            return 900
        case .thirtyMinutes:
            return 1_800
        case .oneHour:
            return 3_600
        case .oneDay:
            return 86_400
        }
    }

    var title: String {
        switch self {
        case .atTime:
            return "准时提醒"
        case .fiveMinutes:
            return "提前 5 分钟"
        case .fifteenMinutes:
            return "提前 15 分钟"
        case .thirtyMinutes:
            return "提前 30 分钟"
        case .oneHour:
            return "提前 1 小时"
        case .oneDay:
            return "提前 1 天"
        }
    }

    var chipTitle: String {
        switch self {
        case .atTime:
            return "准时"
        case .fiveMinutes:
            return "5 分钟"
        case .fifteenMinutes:
            return "15 分钟"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .oneDay:
            return "1 天"
        }
    }

    static func preset(for secondsBeforeTarget: TimeInterval) -> DetailReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

private enum DetailRepeatPreset: CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case weekdays
    case biweekly
    case quarterly
    case halfYear

    var id: String { String(describing: self) }

    func title(anchorDate: Date) -> String {
        makeRule(anchorDate: anchorDate).title(anchorDate: anchorDate)
    }

    func makeRule(anchorDate: Date) -> ItemRepeatRule {
        let calendar = Calendar.current
        switch self {
        case .daily:
            return ItemRepeatRule(frequency: .daily)
        case .weekly:
            return ItemRepeatRule(
                frequency: .weekly,
                weekday: calendar.component(.weekday, from: anchorDate)
            )
        case .monthly:
            return ItemRepeatRule(
                frequency: .monthly,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        case .weekdays:
            return ItemRepeatRule(
                frequency: .weekly,
                weekdays: [2, 3, 4, 5, 6]
            )
        case .biweekly:
            return ItemRepeatRule(
                frequency: .weekly,
                interval: 2,
                weekday: calendar.component(.weekday, from: anchorDate)
            )
        case .quarterly:
            return ItemRepeatRule(
                frequency: .monthly,
                interval: 3,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        case .halfYear:
            return ItemRepeatRule(
                frequency: .monthly,
                interval: 6,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        }
    }
}
