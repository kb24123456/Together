import SwiftUI

/// Each attribute opens directly at its own content in the existing sheet host.
/// All changes still belong to RoutinesViewModel's editor draft.
struct PeriodicTaskAttributeSheet: View {
    let task: PeriodicTask
    @Bindable var viewModel: RoutinesViewModel
    @State private var page: Page
    @State private var contentHeight: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    private enum Page { case schedule, time, reminder }

    init(task: PeriodicTask, viewModel: RoutinesViewModel, source: TaskAttributeEditorTransitionSource) {
        self.task = task
        self.viewModel = viewModel
        _page = State(initialValue: source == .periodicTargetTime ? .time : source == .periodicReminder ? .reminder : .schedule)
    }

    var body: some View {
        Group {
            switch page {
            case .schedule:
                PeriodicPickerSheetSurface(onHeightChange: { contentHeight = $0 }) {
                    VStack(spacing: 16) {
                        cycleSelector
                        if cycle == .daily {
                            Text("每天重复")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(AppTheme.colors.title)
                                .frame(maxWidth: .infinity, minHeight: 76)
                        } else {
                            if cycle == .yearly {
                                annualChoices
                            } else {
                                PeriodicDayStrip(
                                    cycle: cycle, selection: rule?.timing,
                                    onSelect: viewModel.updateDraftTargetDay
                                )
                                .id(cycle)
                            }
                            scheduleFooter
                        }
                    }
                }
            case .time:
                TaskTimePickerSheet(
                    initialDraft: PeriodicTimePickerValue.draft(rule: rule),
                    contextTitle: timeContext,
                    calendar: PeriodicTimePickerValue.calendar,
                    seed: PeriodicTimePickerValue.seed(),
                    onContentHeightChange: { contentHeight = $0 },
                    selectionFeedback: HomeInteractionFeedback.selection
                ) { draft in
                    if let time = draft.selectedTime {
                        let calendar = PeriodicTimePickerValue.calendar
                        viewModel.updateDraftTargetTime(
                            hour: calendar.component(.hour, from: time),
                            minute: calendar.component(.minute, from: time)
                        )
                    } else {
                        viewModel.clearDraftTargetTime()
                    }
                }
            case .reminder:
                PeriodicPickerSheetSurface(onHeightChange: { contentHeight = $0 }) {
                    reminderContent
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .presentationBackground(AppTheme.colors.surface)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.hidden)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var cycleSelector: some View {
        ViewThatFits(in: .horizontal) {
            cycleButtons
            ScrollView(.horizontal) { cycleButtons }
                .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("重复周期")
    }

    private var cycleButtons: some View {
        HStack(spacing: 8) {
            ForEach(PeriodicCycle.allCases, id: \.self) { option in
                Button {
                    guard cycle != option else { return }
                    HomeInteractionFeedback.selection()
                    viewModel.updateDraftCycle(option)
                } label: {
                    Text(option.title)
                        .font(.callout.weight(cycle == option ? .semibold : .regular))
                        .fixedSize()
                        .foregroundStyle(cycle == option ? AppTheme.colors.title : AppTheme.colors.textTertiary)
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(AppTheme.colors.title)
                                .frame(width: 18, height: 3)
                                .opacity(cycle == option ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(cycle == option ? .isSelected : [])
            }
        }
    }

    private var scheduleFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                dayReadout.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                clearDayButton.fixedSize()
            }
            VStack(alignment: .leading, spacing: 16) {
                dayReadout
                clearDayButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var annualChoices: some View {
        let options = PeriodicSchedulePickerValues.days(cycle: .yearly, selected: nil)
        return VStack(spacing: 8) {
            annualChoiceRow(Array(options.prefix(2)))
            ViewThatFits(in: .horizontal) {
                annualChoiceRow(Array(options.dropFirst(2)))
                VStack(spacing: 8) {
                    ForEach(options.dropFirst(2)) { option in annualChoice(option) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("年度目标日")
    }

    private func annualChoiceRow(_ options: [PeriodicDayPickerOption]) -> some View {
        HStack(spacing: 8) {
            ForEach(options) { option in annualChoice(option) }
        }
    }

    private func annualChoice(_ option: PeriodicDayPickerOption) -> some View {
        let selected = rule?.timing == option.timing
        return Button {
            guard !selected else { return }
            HomeInteractionFeedback.selection()
            viewModel.updateDraftTargetDay(option.timing)
        } label: {
            Text(option.title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .fixedSize()
                .foregroundStyle(selected ? AppTheme.colors.surface : AppTheme.colors.body)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? AppTheme.colors.title : AppTheme.colors.pillSurface,
                            in: ConcentricRectangle(corners: .concentric(minimum: .fixed(12)), isUniform: true))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var dayReadout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(cycle.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if cycle == .daily || cycle == .yearly {
                readoutLabel(cycle == .daily ? "每天" : dayTitle, showsMenu: false)
            } else {
                Menu {
                    dateShortcuts
                } label: {
                    readoutLabel(dayTitle, showsMenu: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("目标日，\(dayTitle)")
                .accessibilityHint("轻点快速定位日期或选择特殊规则")
            }
        }
        .containerCornerOffset([.leading, .bottom], sizeToFit: true)
    }

    private func readoutLabel(_ title: String, showsMenu: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .medium))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: title)
                .fixedSize(horizontal: false, vertical: true)
            if showsMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(AppTheme.colors.title)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var clearDayButton: some View {
        if cycle != .daily {
            Button("清除目标日") {
                HomeInteractionFeedback.selection()
                viewModel.clearDraftTargetDay()
            }
            .buttonStyle(PeriodicPickerClearButtonStyle())
            .disabled(rule?.timing == nil)
        }
    }

    @ViewBuilder private var dateShortcuts: some View {
        if cycle == .weekly {
            ForEach(PeriodicSchedulePickerValues.days(cycle: cycle, selected: nil)) { option in
                dayButton(option.title, option.timing)
            }
        } else {
            Section("快速定位") {
                dayButton(cycle == .monthly ? "1号" : "第1天", .dayOfPeriod(1))
                dayButton(cycle == .monthly ? "15号" : "第45天",
                          .dayOfPeriod(cycle == .monthly ? 15 : 45))
                dayButton("最后一天", .daysBeforeEnd(1))
            }
            Section("特殊日期") {
                dayButton("首个工作日", .businessDayOfPeriod(1))
                dayButton("最后一个工作日", .lastBusinessDay)
                if cycle == .monthly {
                    Menu("按周次与周几") {
                        ForEach(PeriodicMonthWeekOrdinal.allCases, id: \.self) { ordinal in
                            Menu(ordinal.title) {
                                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                                    dayButton(RoutineTargetText.absoluteWeekdayText(for: weekday),
                                              .weekdayOfMonth(ordinal: ordinal, weekday: weekday))
                                }
                            }
                        }
                    }
                } else {
                    let lead = cycle == .quarterly ? 14 : 30
                    dayButton("结束前\(lead)天", .daysBeforeEnd(lead))
                }
            }
        }
    }

    private func dayButton(_ title: String, _ timing: PeriodicReminderRule.Timing) -> some View {
        Button(title) {
            HomeInteractionFeedback.selection()
            viewModel.updateDraftTargetDay(timing)
        }
    }

    private var reminderContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提醒").font(.headline)
            if rule?.hasCompleteTarget(for: cycle) == true {
                Picker("提醒时间", selection: Binding(
                    get: { rule?.reminderLeadMinutes },
                    set: { viewModel.updateDraftReminder(leadMinutes: $0) }
                )) {
                    Text("无提醒").tag(nil as Int?)
                    ForEach([0, 5, 15, 30, 60, 1_440], id: \.self) { minutes in
                        Text(reminderTitle(minutes)).tag(Optional(minutes))
                    }
                }
                .pickerStyle(.inline)
                .tint(AppTheme.colors.title)
            } else {
                Text("设置完整目标后即可添加提醒")
                    .font(.callout).foregroundStyle(.secondary)
                if cycle != .daily && rule?.hasTargetDay != true {
                    Button("设置目标日") { page = .schedule }
                        .buttonStyle(PeriodicPickerClearButtonStyle())
                }
                if rule?.hasTargetTime != true {
                    Button("设置时间") { page = .time }
                        .buttonStyle(PeriodicPickerClearButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "准时"
        case 60: return "提前1小时"
        case 1_440: return "提前1天"
        default: return "提前\(minutes)分钟"
        }
    }

    private var cycle: PeriodicCycle { viewModel.activeEditorDraft?.cycle ?? task.cycle }
    private var rule: PeriodicReminderRule? {
        if let draft = viewModel.activeEditorDraft { return draft.reminderRules.first }
        return task.reminderRules.first
    }
    private var dayTitle: String {
        guard let timing = rule?.timing else { return "未设置" }
        let displayed = PeriodicSchedulePickerValues.displayedTiming(timing, cycle: cycle)
        return PeriodicSchedulePickerValues.days(cycle: cycle, selected: timing)
            .first(where: { $0.timing == displayed })?.title ?? "未设置"
    }
    private var timeContext: String {
        if cycle == .daily || rule?.timing == nil { return cycle.title }
        return "\(cycle.title) · \(dayTitle)"
    }
}

private struct PeriodicPickerSheetSurface<Content: View>: View {
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let inset = max(24, geometry.safeAreaInsets.bottom)
            ScrollView {
                content()
                    .padding(.horizontal, inset)
                    .padding(.top, inset)
                    .padding(.bottom, max(0, inset - geometry.safeAreaInsets.bottom))
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppTheme.colors.surface)
    }
}

private struct PeriodicPickerClearButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(isEnabled ? AppTheme.colors.body : AppTheme.colors.textTertiary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(AppTheme.colors.pillSurface,
                        in: ConcentricRectangle(corners: .concentric(minimum: .fixed(16)), isUniform: true))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
