import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeItemDetailSheet: View {
    @Bindable var viewModel: HomeViewModel
    @FocusState private var focusedField: Field?
    @State private var activeMenu: HomeDetailMenu?

    private enum Field: Hashable {
        case title
        case notes
    }

    private enum DetailCategory {
        case task
        case periodic
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.detailDraft != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            editorSection
                            chipSection
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(minHeight: 0, alignment: .top)
                        .padding(.horizontal, 28)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    .scrollIndicators(.hidden)
                    .background(.clear)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.clear)
        .sheet(item: $activeMenu) { menu in
            HomeDetailMenuSheet(menu: menu, viewModel: viewModel)
                .presentationDetents(menu.detents)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
                .modifier(HomeDetailMenuPresentationSizingModifier())
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
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                detailCategory == .periodic ? "周期任务标题" : "任务标题",
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
            .lineLimit(4)
            .focused($focusedField, equals: .notes)
        }
    }

    private var chipSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chips) { chip in
                    Button {
                        HomeInteractionFeedback.selection()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            viewModel.markDetailForExpandedEditing()
                        }
                        activeMenu = chip.menu
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: chip.systemImage)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                            Text(chip.title)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.colors.body.opacity(0.84))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
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
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 6)
    }

    private var detailCategory: DetailCategory {
        viewModel.detailDraft?.repeatRule == nil ? .task : .periodic
    }

    private var chips: [HomeDetailChip] {
        switch detailCategory {
        case .task:
            return [
                HomeDetailChip(systemImage: "calendar", title: taskDateTitle, menu: .date),
                HomeDetailChip(systemImage: "clock", title: taskTimeTitle, menu: .time),
                HomeDetailChip(systemImage: "bell", title: reminderTitle, menu: .reminder),
                HomeDetailChip(
                    systemImage: "flag",
                    title: viewModel.detailDraft?.priority.title ?? "普通",
                    menu: .priority
                )
            ]
        case .periodic:
            return [
                HomeDetailChip(systemImage: "arrow.triangle.2.circlepath", title: repeatTitle, menu: .repeatRule),
                HomeDetailChip(systemImage: "bell", title: reminderTitle, menu: .reminder)
            ]
        }
    }

    private var taskDateTitle: String {
        localizedRelativeMonthDayText(viewModel.detailDraft?.dueAt ?? viewModel.selectedDate)
    }

    private var taskTimeTitle: String {
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "时间" }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else {
            return remindAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        let delta = dueAt.timeIntervalSince(remindAt)
        return HomeDetailReminderPreset.preset(for: delta)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt, calendar: .current)
    }

    private func localizedRelativeMonthDayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M月d日")
        return formatter.string(from: date)
    }

}

private struct HomeDetailChip: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let menu: HomeDetailMenu
}

private struct HomeDetailMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}

private enum HomeDetailMenu: String, Identifiable {
    case date
    case time
    case reminder
    case priority
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(HomeDetailDateMenuDetent.self)]
        case .time:
            return [.fraction(0.5)]
        case .reminder, .priority, .repeatRule:
            return [.fraction(0.46)]
        }
    }
}

private struct HomeDetailDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            HomeDetailDatePickerSheet.preferredHeight + 12,
            context.maxDetentValue * 0.72
        )
    }
}

private struct HomeDetailMenuSheet: View {
    let menu: HomeDetailMenu
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        menuContent
            .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var menuContent: some View {
        switch menu {
        case .date:
            HomeDetailDatePickerSheet(viewModel: viewModel) {
                dismiss()
            }
        case .time:
            HomeDetailTimePickerSheet(
                viewModel: viewModel,
                quickPresetMinutes: viewModel.quickTimePresetMinutes
            ) {
                dismiss()
            }
        case .reminder:
            optionList(options: reminderOptions)
        case .priority:
            optionList(options: priorityOptions)
        case .repeatRule:
            optionList(options: repeatOptions)
        }
    }

    private var reminderOptions: [HomeDetailOptionRow] {
        [HomeDetailOptionRow(title: "不提醒", isSelected: viewModel.detailDraft?.remindAt == nil) {
            viewModel.setDraftReminderEnabled(false)
            dismiss()
        }] + HomeDetailReminderPreset.allCases.map { preset in
            HomeDetailOptionRow(
                title: preset.title,
                isSelected: reminderTitle == preset.chipTitle
            ) {
                ensureDueDateExists()
                let dueAt = viewModel.detailDraft?.dueAt ?? .now
                viewModel.updateDraftReminder(dueAt.addingTimeInterval(-preset.secondsBeforeTarget))
                dismiss()
            }
        }
    }

    private var priorityOptions: [HomeDetailOptionRow] {
        ItemPriority.allCases.map { priority in
            HomeDetailOptionRow(
                title: priority.title,
                isSelected: viewModel.detailDraft?.priority == priority
            ) {
                viewModel.updateDraftPriority(priority)
                dismiss()
            }
        }
    }

    private var repeatOptions: [HomeDetailOptionRow] {
        let anchorDate = viewModel.detailDraft?.dueAt ?? defaultDetailDate
        let selectedTitle = repeatTitle
        return HomeDetailRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: anchorDate)
            return HomeDetailOptionRow(title: title, isSelected: selectedTitle == title) {
                ensureDueDateExists()
                viewModel.updateDraftRepeatRule(preset.makeRule(anchorDate: anchorDate))
                dismiss()
            }
        }
    }

    private func optionList(options: [HomeDetailOptionRow]) -> some View {
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
                        .frame(minHeight: HomeDetailMenuOptionMetrics.height)
                        .padding(.horizontal, 18)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(HomeDetailMenuOptionButtonStyle())
                    .modifier(HomeDetailMenuOptionGlassModifier())
                }
            }
            .padding(HomeDetailMenuOptionMetrics.outerInset)
        }
        .scrollIndicators(.hidden)
        .background(.clear)
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "提醒" }
        let delta = dueAt.timeIntervalSince(remindAt)
        return HomeDetailReminderPreset.preset(for: delta)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt, calendar: .current)
    }

    private var defaultDetailDate: Date {
        viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }
}

private struct HomeDetailDatePickerSheet: View {
    static let gridRowHeight: CGFloat = 36
    static let gridRowSpacing: CGFloat = 10
    static let gridColumnSpacing: CGFloat = 0
    static let weekdayRowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 8
    static let topBottomPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 10
    static let headerToGridSpacing: CGFloat = 10
    static let calendarGridHeight: CGFloat =
        (gridRowHeight * 6)
        + (gridRowSpacing * 5)
    static let preferredHeight: CGFloat =
        (topBottomPadding * 2)
        + headerHeight
        + headerToGridSpacing
        + weekdayRowHeight
        + contentSpacing
        + calendarGridHeight

    @Bindable var viewModel: HomeViewModel
    let onDismiss: () -> Void
    @State private var displayedMonth: Date
    @State private var transitionDirection: HomeDetailMonthTransitionDirection = .forward

    init(viewModel: HomeViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss

        let calendar = Calendar.current
        let initialDate = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        _displayedMonth = State(
            initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let headerInset = headerHorizontalInset(for: proxy.size.width)

            VStack(alignment: .leading, spacing: Self.headerToGridSpacing) {
                HStack(spacing: 10) {
                    Text(monthTitle)
                        .font(AppTheme.typography.sized(21, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        calendarButton(systemName: "chevron.left") {
                            shiftMonth(by: -1)
                        }

                        Button("Today") {
                            HomeInteractionFeedback.selection()
                            selectDate(Date())
                        }
                        .buttonStyle(.plain)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(minWidth: 84, minHeight: 40)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )

                        calendarButton(systemName: "chevron.right") {
                            shiftMonth(by: 1)
                        }
                    }
                }
                .frame(height: Self.headerHeight)
                .padding(.horizontal, headerInset)

                VStack(spacing: Self.contentSpacing) {
                    LazyVGrid(
                        columns: calendarColumns,
                        spacing: Self.gridColumnSpacing
                    ) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.weekdayRowHeight)
                        }
                    }

                    LazyVGrid(
                        columns: calendarColumns,
                        spacing: Self.gridRowSpacing
                    ) {
                        ForEach(monthCells) { cell in
                            Button {
                                HomeInteractionFeedback.selection()
                                selectDate(cell.date)
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(
                                            isToday(cell.date) && !isSelected(cell.date)
                                            ? AppTheme.colors.coral
                                            : .clear,
                                            lineWidth: 1.6
                                        )
                                        .background(
                                            Circle()
                                                .fill(isSelected(cell.date) ? AppTheme.colors.coral : .clear)
                                        )

                                    Text("\(Calendar.current.component(.day, from: cell.date))")
                                        .font(AppTheme.typography.sized(18, weight: .semibold))
                                        .foregroundStyle(dayTextColor(for: cell))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.gridRowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: Self.calendarGridHeight, alignment: .top)
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .id(monthIdentity)
        .transition(monthTransition)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: displayedMonth)
        .padding(.vertical, Self.topBottomPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gridColumnSpacing), count: 7)
    }

    private func headerHorizontalInset(for availableWidth: CGFloat) -> CGFloat {
        let gridWidth = max(availableWidth - (Self.horizontalPadding * 2), 0)
        let columnWidth = max((gridWidth - (Self.gridColumnSpacing * 6)) / 7, 0)
        let firstColumnCenterX = Self.horizontalPadding + (columnWidth / 2)
        let visualDayHalfWidth = min(widestDayLabelWidth, columnWidth) / 2
        return max(firstColumnCenterX - visualDayHalfWidth, Self.horizontalPadding)
    }

    private var selectedDate: Date {
        viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var monthIdentity: String {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private var monthTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection.insertionEdge).combined(with: .opacity),
            removal: .move(edge: transitionDirection.removalEdge).combined(with: .opacity)
        )
    }

    private var widestDayLabelWidth: CGFloat {
        #if canImport(UIKit)
        let font = AppTheme.typography.sizedUIFont(18, weight: .semibold)
        return (1...31)
            .map { "\($0)" }
            .map { NSString(string: $0).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        #else
        return 0
        #endif
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthCells: [HomeDetailCalendarDayCell] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [HomeDetailCalendarDayCell] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            cells.append(
                HomeDetailCalendarDayCell(
                    date: current,
                    isInDisplayedMonth: calendar.isDate(current, equalTo: displayedMonth, toGranularity: .month)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }
        return cells
    }

    private func calendarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTheme.typography.sized(15, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        transitionDirection = amount >= 0 ? .forward : .backward
        HomeInteractionFeedback.selection()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
    }

    private func selectDate(_ date: Date) {
        viewModel.updateDraftDueDate(Calendar.current.startOfDay(for: date))
        onDismiss()
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayTextColor(for cell: HomeDetailCalendarDayCell) -> Color {
        if isSelected(cell.date) {
            return .white
        }
        if isToday(cell.date) {
            return AppTheme.colors.coral
        }
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.52)
    }
}

private struct HomeDetailTimePickerSheet: View {
    @Bindable var viewModel: HomeViewModel
    let quickPresetMinutes: [Int]
    let onDismiss: () -> Void
    @State private var selectedTime: Date

    init(
        viewModel: HomeViewModel,
        quickPresetMinutes: [Int],
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.quickPresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(quickPresetMinutes)
        self.onDismiss = onDismiss

        let detailDate = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        let baseTime = viewModel.detailDraft?.dueAt
            ?? Self.roundedTimeSeed(for: detailDate)
            ?? detailDate
        _selectedTime = State(initialValue: baseTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(quickPresetMinutes, id: \.self) { minutes in
                    Button {
                        HomeInteractionFeedback.selection()
                        applyQuickPreset(minutes)
                    } label: {
                        Text(relativePresetTitle(minutes))
                            .font(AppTheme.typography.sized(15, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(HomeDetailMenuOptionButtonStyle())
                    .modifier(HomeDetailMenuOptionGlassModifier())
                }
            }
            .padding(.top, HomeDetailTimePickerMetrics.verticalInset)
            .padding(.horizontal, HomeDetailMenuOptionMetrics.outerInset)
            .padding(.bottom, HomeDetailTimePickerMetrics.contentSpacing)

            HomeDetailMinuteIntervalWheelPicker(
                selection: $selectedTime,
                minuteInterval: 5
            )
            .frame(maxWidth: .infinity)
            .frame(height: HomeDetailTimePickerMetrics.pickerHeight)
            .clipped()
            .padding(.bottom, HomeDetailTimePickerMetrics.contentSpacing)

            HStack {
                Button {
                    HomeInteractionFeedback.selection()
                    saveSelection()
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        Text("添加")
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: HomeDetailMenuOptionMetrics.height)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(HomeDetailMenuOptionButtonStyle())
                .modifier(HomeDetailMenuOptionGlassModifier())
            }
            .padding(.horizontal, HomeDetailMenuOptionMetrics.outerInset)
            .padding(.bottom, HomeDetailTimePickerMetrics.verticalInset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private static func roundedTimeSeed(for date: Date) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let roundedMinute = Int((Double(minute) / 5).rounded()) * 5
        let minuteOverflow = roundedMinute / 60
        let normalizedMinute = roundedMinute % 60
        let normalizedHour = (hour + minuteOverflow) % 24

        return calendar.date(
            bySettingHour: normalizedHour,
            minute: normalizedMinute,
            second: 0,
            of: date
        )
    }

    private static func offsetTimeSeed(minutesFromNow: Int, for date: Date) -> Date {
        let calendar = Calendar.current
        let future = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        let components = calendar.dateComponents([.hour, .minute], from: future)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    private func applyQuickPreset(_ minutes: Int) {
        let date = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        let presetTime = Self.offsetTimeSeed(minutesFromNow: minutes, for: date)
        selectedTime = presetTime
        saveSelection(presetTime)
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }

    private func saveSelection(_ value: Date? = nil) {
        ensureDueDateExists()
        viewModel.updateDraftDueTime(value ?? selectedTime)
        onDismiss()
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }
}

private struct HomeDetailMinuteIntervalWheelPicker: UIViewRepresentable {
    @Binding var selection: Date
    let minuteInterval: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.locale = Locale(identifier: "zh_CN")
        picker.minuteInterval = minuteInterval
        picker.setDate(Self.rounded(selection, minuteInterval: minuteInterval), animated: false)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.didChange(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        let roundedSelection = Self.rounded(selection, minuteInterval: minuteInterval)

        if abs(selection.timeIntervalSince(roundedSelection)) > 0.5 {
            DispatchQueue.main.async {
                selection = roundedSelection
            }
        }

        if abs(uiView.date.timeIntervalSince(roundedSelection)) > 0.5 {
            uiView.setDate(roundedSelection, animated: context.coordinator.hasAppeared)
        }

        context.coordinator.hasAppeared = true
    }

    private static func rounded(_ date: Date, minuteInterval: Int) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let roundedMinute = Int((Double(minute) / Double(minuteInterval)).rounded()) * minuteInterval

        let hourBaseDate = calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date

        return calendar.date(byAdding: .minute, value: roundedMinute, to: hourBaseDate) ?? hourBaseDate
    }

    final class Coordinator: NSObject {
        var parent: HomeDetailMinuteIntervalWheelPicker
        var hasAppeared = false

        init(_ parent: HomeDetailMinuteIntervalWheelPicker) {
            self.parent = parent
        }

        @objc func didChange(_ sender: UIDatePicker) {
            parent.selection = HomeDetailMinuteIntervalWheelPicker.rounded(
                sender.date,
                minuteInterval: parent.minuteInterval
            )
        }
    }
}

private struct HomeDetailOptionRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private struct HomeDetailCalendarDayCell: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

private enum HomeDetailMonthTransitionDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        switch self {
        case .forward:
            return .trailing
        case .backward:
            return .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward:
            return .leading
        case .backward:
            return .trailing
        }
    }
}

private enum HomeDetailReminderPreset: CaseIterable, Identifiable {
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

    static func preset(for secondsBeforeTarget: TimeInterval) -> HomeDetailReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

private enum HomeDetailRepeatPreset: CaseIterable, Identifiable {
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

private struct HomeDetailMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private struct HomeDetailMenuOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private enum HomeDetailMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

private enum HomeDetailTimePickerMetrics {
    static let verticalInset: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let pickerHeight: CGFloat = 170
}
