import SwiftUI
#if canImport(UIKit)
import UIKit
import CoreText
#endif

enum TaskEditorMenu: String, Identifiable {
    case date
    case time
    case reminder
    case priority
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(TaskEditorDateMenuDetent.self)]
        case .time:
            return [.fraction(0.5)]
        case .reminder, .priority, .repeatRule:
            return [.fraction(0.46)]
        }
    }
}

struct TaskEditorChipSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let menu: TaskEditorMenu
    let semanticValue: TaskEditorChipSemanticValue
    let showsTrailingClear: Bool

    init(
        id: String,
        title: String,
        systemImage: String,
        menu: TaskEditorMenu,
        semanticValue: TaskEditorChipSemanticValue,
        showsTrailingClear: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.menu = menu
        self.semanticValue = semanticValue
        self.showsTrailingClear = showsTrailingClear
    }
}

struct TaskEditorRenderedChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let menu: TaskEditorMenu
    let showsTrailingClear: Bool
    let transitionDirection: TaskEditorChipTextTransitionDirection
    let semanticValue: TaskEditorChipSemanticValue
}

enum TaskEditorChipSemanticValue: Equatable {
    case date(Date)
    case optionalDate(Date?)
    case time(Date?)
    case reminder(TimeInterval?)
    case priority(Int)
    case repeatRule(title: String, rank: Int)

    static func direction(
        from previousValue: TaskEditorChipSemanticValue,
        to newValue: TaskEditorChipSemanticValue
    ) -> TaskEditorChipTextTransitionDirection {
        switch (previousValue, newValue) {
        case let (.date(oldDate), .date(newDate)):
            return newDate >= oldDate ? .up : .down
        case let (.optionalDate(oldDate), .optionalDate(newDate)):
            return compare(date: oldDate, with: newDate)
        case let (.date(oldDate), .optionalDate(newDate)):
            return compare(date: oldDate, with: newDate)
        case let (.optionalDate(oldDate), .date(newDate)):
            return compare(date: oldDate, with: newDate)
        case let (.time(oldDate), .time(newDate)):
            return compare(date: oldDate, with: newDate)
        case let (.reminder(oldOffset), .reminder(newOffset)):
            return compare(value: oldOffset, with: newOffset)
        case let (.priority(oldRank), .priority(newRank)):
            return newRank >= oldRank ? .up : .down
        case let (.repeatRule(_, oldRank), .repeatRule(_, newRank)):
            return newRank >= oldRank ? .up : .down
        default:
            return .up
        }
    }

    private static func compare(date oldDate: Date?, with newDate: Date?) -> TaskEditorChipTextTransitionDirection {
        switch (oldDate, newDate) {
        case let (lhs?, rhs?):
            return rhs >= lhs ? .up : .down
        case (nil, .some):
            return .up
        case (.some, nil):
            return .down
        case (nil, nil):
            return .up
        }
    }

    private static func compare(
        value oldValue: TimeInterval?,
        with newValue: TimeInterval?
    ) -> TaskEditorChipTextTransitionDirection {
        switch (oldValue, newValue) {
        case let (lhs?, rhs?):
            return rhs >= lhs ? .up : .down
        case (nil, .some):
            return .up
        case (.some, nil):
            return .down
        case (nil, nil):
            return .up
        }
    }
}

enum TaskEditorChipTextTransitionDirection {
    case up
    case down
}

struct TaskEditorChipRow: View {
    let chips: [TaskEditorRenderedChip]
    let namespace: Namespace.ID
    let trailingInset: CGFloat
    let onChipTap: (TaskEditorMenu) -> Void
    let onClearTap: (TaskEditorRenderedChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chips) { chip in
                    HStack(spacing: chip.showsTrailingClear ? 8 : 3) {
                        Button {
                            onChipTap(chip.menu)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: chip.systemImage)
                                    .font(AppTheme.typography.sized(14, weight: .semibold))

                                TaskEditorAnimatedChipTitle(
                                    text: chip.title,
                                    semanticValue: chip.semanticValue,
                                    direction: chip.transitionDirection,
                                    font: AppTheme.typography.sized(14, weight: .semibold),
                                    uiFont: AppTheme.typography.sizedUIFont(14, weight: .semibold)
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if chip.showsTrailingClear {
                            Button {
                                onClearTap(chip)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(AppTheme.typography.sized(11, weight: .bold))
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(AppTheme.colors.body.opacity(0.84))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .modifier(
                        TaskEditorChipSurfaceModifier(
                            animationID: chip.id,
                            namespace: namespace
                        )
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 10)),
                            removal: .opacity.combined(with: .offset(x: -10))
                        )
                    )
                }
            }
            .padding(.trailing, trailingInset)
            .padding(.vertical, 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: chips.map(\.id).joined(separator: "|"))
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TaskEditorOptionRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

struct TaskEditorOptionList: View {
    let options: [TaskEditorOptionRow]
    let selectionFeedback: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        selectionFeedback()
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
                        .frame(minHeight: TaskEditorMenuOptionMetrics.height)
                        .padding(.horizontal, 18)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(TaskEditorMenuOptionButtonStyle())
                    .modifier(TaskEditorMenuOptionGlassModifier())
                }
            }
            .padding(TaskEditorMenuOptionMetrics.outerInset)
        }
        .scrollIndicators(.hidden)
        .background(.clear)
    }
}

struct TaskEditorDatePickerSheet: View {
    static let gridRowHeight: CGFloat = 36
    static let gridRowSpacing: CGFloat = 10
    static let gridColumnSpacing: CGFloat = 0
    static let weekdayRowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 8
    static let topBottomPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 10
    static let headerToGridSpacing: CGFloat = 10
    static let calendarGridHeight: CGFloat = (gridRowHeight * 6) + (gridRowSpacing * 5)
    static let preferredHeight: CGFloat =
        (topBottomPadding * 2) + headerHeight + headerToGridSpacing + weekdayRowHeight + contentSpacing + calendarGridHeight

    @Binding var selectedDate: Date
    let selectionFeedback: () -> Void
    let onDismiss: () -> Void
    @State private var displayedMonth: Date
    @State private var transitionDirection: TaskEditorMonthTransitionDirection = .forward

    init(
        selectedDate: Binding<Date>,
        selectionFeedback: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _selectedDate = selectedDate
        self.selectionFeedback = selectionFeedback
        self.onDismiss = onDismiss
        let calendar = Calendar.current
        let initialDate = selectedDate.wrappedValue
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
                            selectionFeedback()
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
                    LazyVGrid(columns: calendarColumns, spacing: Self.gridColumnSpacing) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.weekdayRowHeight)
                        }
                    }

                    LazyVGrid(columns: calendarColumns, spacing: Self.gridRowSpacing) {
                        ForEach(monthCells) { cell in
                            Button {
                                selectionFeedback()
                                selectDate(cell.date)
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(
                                            isToday(cell.date) && !isSelected(cell.date) ? AppTheme.colors.coral : .clear,
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

    private var weekdaySymbols: [String] { ["日", "一", "二", "三", "四", "五", "六"] }

    private var monthCells: [TaskEditorCalendarDayCell] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [TaskEditorCalendarDayCell] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            cells.append(
                TaskEditorCalendarDayCell(
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
        selectionFeedback()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
    }

    private func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        onDismiss()
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayTextColor(for cell: TaskEditorCalendarDayCell) -> Color {
        if isSelected(cell.date) { return .white }
        if isToday(cell.date) { return AppTheme.colors.coral }
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.52)
    }
}

struct TaskEditorTimePickerSheet: View {
    @Binding var selectedTime: Date?
    let anchorDate: Date
    let quickPresetMinutes: [Int]
    let primaryButtonTitle: String
    let selectionFeedback: () -> Void
    let primaryFeedback: () -> Void
    let onDismiss: () -> Void
    @State private var stagedTime: Date

    init(
        selectedTime: Binding<Date?>,
        anchorDate: Date,
        quickPresetMinutes: [Int],
        primaryButtonTitle: String = "添加",
        selectionFeedback: @escaping () -> Void,
        primaryFeedback: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _selectedTime = selectedTime
        self.anchorDate = anchorDate
        self.quickPresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(quickPresetMinutes)
        self.primaryButtonTitle = primaryButtonTitle
        self.selectionFeedback = selectionFeedback
        self.primaryFeedback = primaryFeedback
        self.onDismiss = onDismiss
        let baseTime = selectedTime.wrappedValue
            ?? Self.roundedTimeSeed(for: anchorDate)
            ?? anchorDate
        _stagedTime = State(initialValue: baseTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(quickPresetMinutes, id: \.self) { minutes in
                    Button {
                        selectionFeedback()
                        applyQuickPreset(minutes)
                    } label: {
                        Text(relativePresetTitle(minutes))
                            .font(AppTheme.typography.sized(15, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(TaskEditorMenuOptionButtonStyle())
                    .modifier(TaskEditorMenuOptionGlassModifier())
                }
            }
            .padding(.top, TaskEditorTimePickerMetrics.verticalInset)
            .padding(.horizontal, TaskEditorMenuOptionMetrics.outerInset)
            .padding(.bottom, TaskEditorTimePickerMetrics.contentSpacing)

            TaskEditorMinuteIntervalWheelPicker(
                selection: $stagedTime,
                minuteInterval: 5
            )
            .frame(maxWidth: .infinity)
            .frame(height: TaskEditorTimePickerMetrics.pickerHeight)
            .clipped()
            .padding(.bottom, TaskEditorTimePickerMetrics.contentSpacing)

            HStack {
                Button {
                    primaryFeedback()
                    saveSelection()
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        Text(primaryButtonTitle)
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: TaskEditorMenuOptionMetrics.height)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(TaskEditorMenuOptionButtonStyle())
                .modifier(TaskEditorMenuOptionGlassModifier())
            }
            .padding(.horizontal, TaskEditorMenuOptionMetrics.outerInset)
            .padding(.bottom, TaskEditorTimePickerMetrics.verticalInset)
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
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    private func applyQuickPreset(_ minutes: Int) {
        let presetTime = Self.offsetTimeSeed(minutesFromNow: minutes, for: anchorDate)
        stagedTime = presetTime
        saveSelection(presetTime)
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }

    private func saveSelection(_ value: Date? = nil) {
        selectedTime = value ?? stagedTime
        onDismiss()
    }
}

struct TaskEditorMinuteIntervalWheelPicker: UIViewRepresentable {
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
        let hourBaseDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        return calendar.date(byAdding: .minute, value: roundedMinute, to: hourBaseDate) ?? hourBaseDate
    }

    final class Coordinator: NSObject {
        var parent: TaskEditorMinuteIntervalWheelPicker
        var hasAppeared = false

        init(_ parent: TaskEditorMinuteIntervalWheelPicker) {
            self.parent = parent
        }

        @objc func didChange(_ sender: UIDatePicker) {
            parent.selection = TaskEditorMinuteIntervalWheelPicker.rounded(
                sender.date,
                minuteInterval: parent.minuteInterval
            )
        }
    }
}

enum TaskEditorReminderPreset: CaseIterable, Identifiable {
    case atTime
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay

    var id: String { title }

    var secondsBeforeTarget: TimeInterval {
        switch self {
        case .atTime: return 0
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1_800
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        }
    }

    var title: String {
        switch self {
        case .atTime: return "准时提醒"
        case .fiveMinutes: return "提前 5 分钟"
        case .fifteenMinutes: return "提前 15 分钟"
        case .thirtyMinutes: return "提前 30 分钟"
        case .oneHour: return "提前 1 小时"
        case .oneDay: return "提前 1 天"
        }
    }

    var chipTitle: String {
        switch self {
        case .atTime: return "准时"
        case .fiveMinutes: return "5 分钟"
        case .fifteenMinutes: return "15 分钟"
        case .thirtyMinutes: return "30 分钟"
        case .oneHour: return "1 小时"
        case .oneDay: return "1 天"
        }
    }

    static func preset(for secondsBeforeTarget: TimeInterval) -> TaskEditorReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

enum TaskEditorRepeatPreset: CaseIterable, Identifiable {
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

struct TaskEditorMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}

struct TaskEditorChipSurfaceModifier: ViewModifier {
    let animationID: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .matchedGeometryEffect(
                        id: "taskEditor.chip.\(animationID)",
                        in: namespace
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
            }
    }
}

struct TaskEditorMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                    .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

struct TaskEditorMenuOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

enum TaskEditorMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

enum TaskEditorTimePickerMetrics {
    static let verticalInset: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let pickerHeight: CGFloat = 170
}

enum TaskEditorChipAnimation {
    static let textSpring = Animation.easeInOut(duration: 0.7)
    static let layoutSpring = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let widthExpansionLead: TimeInterval = 0.12
}

private struct TaskEditorDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            TaskEditorDatePickerSheet.preferredHeight + 12,
            context.maxDetentValue * 0.72
        )
    }
}

private struct TaskEditorCalendarDayCell: Identifiable {
    let id = UUID()
    let date: Date
    let isInDisplayedMonth: Bool
}

private enum TaskEditorMonthTransitionDirection {
    case forward
    case backward

    var insertionEdge: Edge { self == .forward ? .trailing : .leading }
    var removalEdge: Edge { self == .forward ? .leading : .trailing }
}

private struct TaskEditorChipTextSegment: Identifiable, Equatable {
    enum Kind {
        case numeric
        case text
    }

    let id: String
    let text: String
    let kind: Kind

    static func empty(id: String, kind: Kind) -> Self {
        Self(id: id, text: "", kind: kind)
    }

    func measuredWidth(using font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

private struct TaskEditorChipTextLayout: Equatable {
    let segments: [TaskEditorChipTextSegment]

    init(text: String, semanticValue: TaskEditorChipSemanticValue) {
        switch semanticValue {
        case let .date(date):
            segments = Self.dateSegments(for: date)
        case let .optionalDate(date):
            if let date {
                segments = Self.dateSegments(for: date)
            } else {
                segments = [TaskEditorChipTextSegment(id: "main", text: text, kind: .text)]
            }
        case let .time(date):
            segments = Self.timeSegments(for: date, placeholder: text)
        case .reminder, .priority, .repeatRule:
            segments = [TaskEditorChipTextSegment(id: "main", text: text, kind: .text)]
        }
    }

    private static func dateSegments(for date: Date) -> [TaskEditorChipTextSegment] {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return [
                TaskEditorChipTextSegment(id: "relative", text: "今天", kind: .text),
                .empty(id: "monthTens", kind: .numeric),
                .empty(id: "monthOnes", kind: .numeric),
                .empty(id: "monthSuffix", kind: .text),
                .empty(id: "dayTens", kind: .numeric),
                .empty(id: "dayOnes", kind: .numeric),
                .empty(id: "daySuffix", kind: .text)
            ]
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return [
                TaskEditorChipTextSegment(id: "relative", text: "明天", kind: .text),
                .empty(id: "monthTens", kind: .numeric),
                .empty(id: "monthOnes", kind: .numeric),
                .empty(id: "monthSuffix", kind: .text),
                .empty(id: "dayTens", kind: .numeric),
                .empty(id: "dayOnes", kind: .numeric),
                .empty(id: "daySuffix", kind: .text)
            ]
        }

        let monthSegments = numberSegments(prefix: "month", value: calendar.component(.month, from: date), digits: 2, blankLeadingZero: true)
        let daySegments = numberSegments(prefix: "day", value: calendar.component(.day, from: date), digits: 2, blankLeadingZero: true)
        return [
            .empty(id: "relative", kind: .text),
            monthSegments[0],
            monthSegments[1],
            TaskEditorChipTextSegment(id: "monthSuffix", text: "月", kind: .text),
            daySegments[0],
            daySegments[1],
            TaskEditorChipTextSegment(id: "daySuffix", text: "日", kind: .text)
        ]
    }

    private static func timeSegments(for date: Date?, placeholder: String) -> [TaskEditorChipTextSegment] {
        guard let date else {
            return [
                TaskEditorChipTextSegment(id: "placeholder", text: placeholder, kind: .text),
                .empty(id: "hourTens", kind: .numeric),
                .empty(id: "hourOnes", kind: .numeric),
                .empty(id: "separator", kind: .text),
                .empty(id: "minuteTens", kind: .numeric),
                .empty(id: "minuteOnes", kind: .numeric)
            ]
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        let formatted = formatter.string(from: date)
        let components = formatted.split(separator: ":").map(String.init)
        let hour = Int(components.indices.contains(0) ? components[0] : "") ?? 0
        let minute = Int(components.indices.contains(1) ? components[1] : "") ?? 0
        let hourSegments = numberSegments(prefix: "hour", value: hour, digits: 2, blankLeadingZero: false)
        let minuteSegments = numberSegments(prefix: "minute", value: minute, digits: 2, blankLeadingZero: false)

        return [
            .empty(id: "placeholder", kind: .text),
            hourSegments[0],
            hourSegments[1],
            TaskEditorChipTextSegment(id: "separator", text: ":", kind: .text),
            minuteSegments[0],
            minuteSegments[1]
        ]
    }

    private static func numberSegments(
        prefix: String,
        value: Int,
        digits: Int,
        blankLeadingZero: Bool
    ) -> [TaskEditorChipTextSegment] {
        let formatted = String(format: "%0\(digits)d", value)
        return formatted.enumerated().map { index, character in
            let isLeadingZero = blankLeadingZero && index == 0 && character == "0"
            return TaskEditorChipTextSegment(
                id: "\(prefix)\(index)",
                text: isLeadingZero ? "" : String(character),
                kind: .numeric
            )
        }
    }
}

private struct TaskEditorAnimatedChipTitle: View {
    let text: String
    let semanticValue: TaskEditorChipSemanticValue
    let direction: TaskEditorChipTextTransitionDirection
    let font: Font
    let uiFont: UIFont

    @State private var displayedText: String
    @State private var displayedWidth: CGFloat
    @State private var transitionToken = UUID()

    init(
        text: String,
        semanticValue: TaskEditorChipSemanticValue,
        direction: TaskEditorChipTextTransitionDirection,
        font: Font,
        uiFont: UIFont
    ) {
        self.text = text
        self.semanticValue = semanticValue
        self.direction = direction
        self.font = font
        self.uiFont = uiFont
        _displayedText = State(initialValue: text)
        _displayedWidth = State(initialValue: Self.measuredWidth(text: text, semanticValue: semanticValue, using: uiFont))
    }

    var body: some View {
        token(displayedText)
            .frame(width: displayedWidth, height: 22, alignment: .center)
            .frame(height: 22, alignment: .center)
            .clipped()
            .onChange(of: text) { oldValue, newValue in
                guard oldValue != newValue else { return }
                syncTransition(to: newValue)
            }
    }

    private func syncTransition(to newText: String) {
        let targetWidth = Self.measuredWidth(text: newText, semanticValue: semanticValue, using: uiFont)
        let token = UUID()
        transitionToken = token

        if targetWidth > displayedWidth {
            withAnimation(TaskEditorChipAnimation.layoutSpring) {
                displayedWidth = targetWidth
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + TaskEditorChipAnimation.widthExpansionLead) {
                guard transitionToken == token else { return }
                withAnimation(TaskEditorChipAnimation.textSpring) {
                    displayedText = newText
                }
            }
        } else {
            withAnimation(TaskEditorChipAnimation.textSpring) {
                displayedText = newText
            }
            withAnimation(TaskEditorChipAnimation.layoutSpring) {
                displayedWidth = targetWidth
            }
        }
    }

    @ViewBuilder
    private func token(_ value: String) -> some View {
        if value.isEmpty {
            Text("")
                .font(font)
                .lineLimit(1)
        } else {
            switch contentTransitionStyle {
            case .numeric:
                Text(value)
                    .font(font)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: direction == .down))
                    .lineLimit(1)
            case .interpolated:
                Text(value)
                    .font(font)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
            case .none:
                Text(value)
                    .font(font)
                    .lineLimit(1)
            }
        }
    }

    private var contentTransitionStyle: TaskEditorChipContentTransitionStyle {
        switch semanticValue {
        case .date, .optionalDate, .time, .reminder:
            return .numeric
        case .priority, .repeatRule:
            return .interpolated
        }
    }

    private static func measure(text: String, using font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func measuredWidth(
        text: String,
        semanticValue: TaskEditorChipSemanticValue,
        using font: UIFont
    ) -> CGFloat {
        let measuredFont = measuredFont(for: semanticValue, baseFont: font)
        return measure(text: text, using: measuredFont) + measurementPadding(for: semanticValue)
    }

    private static func measuredFont(
        for semanticValue: TaskEditorChipSemanticValue,
        baseFont: UIFont
    ) -> UIFont {
        guard usesNumericTransition(for: semanticValue) else { return baseFont }
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }

    private static func measurementPadding(for semanticValue: TaskEditorChipSemanticValue) -> CGFloat {
        usesNumericTransition(for: semanticValue) ? 8 : 6
    }

    private static func usesNumericTransition(for semanticValue: TaskEditorChipSemanticValue) -> Bool {
        switch semanticValue {
        case .date, .optionalDate, .time, .reminder:
            return true
        case .priority, .repeatRule:
            return false
        }
    }
}

private enum TaskEditorChipContentTransitionStyle {
    case numeric
    case interpolated
    case none
}

extension ItemPriority {
    var animationRank: Int {
        switch self {
        case .normal:
            return 0
        case .important:
            return 1
        case .critical:
            return 2
        }
    }
}

extension ItemRepeatRule {
    var animationRank: Int {
        switch frequency {
        case .daily:
            return interval == 1 ? 0 : interval
        case .weekly:
            if weekdays == [2, 3, 4, 5, 6] {
                return 2
            }
            if interval == 2 {
                return 4
            }
            return 3
        case .monthly:
            switch interval {
            case 6:
                return 7
            case 3:
                return 6
            default:
                return 5
            }
        }
    }
}
