import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ComposerPlaceholderSheet: View {
    let route: ComposerRoute
    let appContext: AppContext

    @Environment(\.dismiss) private var dismiss
    @State private var draftState: ComposerDraftState
    @State private var activeMenu: ComposerMenu?
    @State private var isSaving = false
    @State private var lastFocusedFieldBeforeMenu: ComposerField?
    @FocusState private var focusedField: ComposerField?

    init(route: ComposerRoute, appContext: AppContext) {
        self.route = route
        self.appContext = appContext
        _draftState = State(
            initialValue: ComposerDraftState(
                initialCategory: route == .newProject ? .project : .task,
                referenceDate: appContext.homeViewModel.selectedDate
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                categorySwitcher
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                TabView(selection: $draftState.category) {
                    ForEach(ComposerCategory.allCases) { category in
                        ComposerPage(
                            category: category,
                            draftState: $draftState,
                            focusedField: $focusedField
                        )
                        .tag(category)
                        .padding(.horizontal, 26)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.26, dampingFraction: 0.84), value: draftState.category)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.colors.surface)
            .overlay(alignment: .bottom) {
                bottomActionArea(bottomInset: max(proxy.safeAreaInsets.bottom, 8))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(item: $activeMenu, onDismiss: restoreKeyboardFocusIfNeeded) { menu in
            ComposerMenuSheet(
                menu: menu,
                draftState: $draftState,
                onDismiss: dismissActiveMenu
            )
            .presentationDetents(menu.detents)
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(false)
            .modifier(ComposerMenuPresentationSizingModifier())
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                focusedField = .title
            }
        }
    }

    private var categorySwitcher: some View {
        HStack(spacing: 10) {
            ForEach(ComposerCategory.allCases) { category in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        draftState.category = category
                    }
                } label: {
                    Text(category.title)
                        .font(AppTheme.typography.sized(18, weight: draftState.category == category ? .bold : .semibold))
                        .foregroundStyle(
                            draftState.category == category
                            ? AppTheme.colors.title
                            : AppTheme.colors.textTertiary
                        )
                        .padding(.horizontal, 17)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(draftState.category == category ? AppTheme.colors.surfaceElevated : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 10)
    }

    private func bottomActionArea(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                chipRow

                if draftState.hasMeaningfulContent {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        Text(addButtonTitle)
                            .font(AppTheme.typography.sized(15, weight: .bold))
                            .foregroundStyle(AppTheme.colors.coral)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.95))
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(.white.opacity(0.88), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [.clear, AppTheme.colors.surface.opacity(0.97)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(.bottom, bottomInset)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: draftState.hasMeaningfulContent)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chipsForCurrentCategory) { chip in
                    Button {
                        openMenu(chip.menu)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: chip.systemImage)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                            Text(chip.title)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.colors.body.opacity(0.84))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .modifier(ComposerChipSurfaceModifier())
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipsForCurrentCategory: [ComposerChip] {
        switch draftState.category {
        case .periodic:
            return [
                ComposerChip(
                    title: draftState.repeatSummaryText,
                    systemImage: "arrow.triangle.2.circlepath",
                    menu: .repeatRule
                ),
                ComposerChip(
                    title: draftState.reminderSummaryText(for: .periodic),
                    systemImage: "bell",
                    menu: .reminder
                )
            ]
        case .task:
            return [
                ComposerChip(
                    title: draftState.taskDateText,
                    systemImage: "calendar",
                    menu: .date
                ),
                ComposerChip(
                    title: draftState.taskTimeText,
                    systemImage: "clock",
                    menu: .time
                ),
                ComposerChip(
                    title: draftState.reminderSummaryText(for: .task),
                    systemImage: "bell",
                    menu: .reminder
                ),
                ComposerChip(
                    title: draftState.priority.title,
                    systemImage: "flag",
                    menu: .priority
                )
            ]
        case .project:
            return [
                ComposerChip(
                    title: draftState.projectDateText,
                    systemImage: "calendar",
                    menu: .date
                ),
                ComposerChip(
                    title: draftState.reminderSummaryText(for: .project),
                    systemImage: "bell",
                    menu: .reminder
                ),
                ComposerChip(
                    title: draftState.priority.title,
                    systemImage: "flag",
                    menu: .priority
                )
            ]
        }
    }
    private var addButtonTitle: String {
        draftState.category == .project ? "创建" : "添加"
    }

    private func openMenu(_ menu: ComposerMenu) {
        lastFocusedFieldBeforeMenu = focusedField
        focusedField = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                activeMenu = menu
            }
        }
    }

    private func restoreKeyboardFocusIfNeeded() {
        guard let field = lastFocusedFieldBeforeMenu else { return }
        lastFocusedFieldBeforeMenu = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusedField = field
        }
    }

    private func dismissActiveMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            activeMenu = nil
        }
        restoreKeyboardFocusIfNeeded()
    }

    @MainActor
    private func save() async {
        guard draftState.hasMeaningfulContent else { return }
        guard
            let spaceID = appContext.sessionStore.currentSpace?.id,
            let actorID = appContext.sessionStore.currentUser?.id
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            switch draftState.category {
            case .periodic, .task:
                _ = try await appContext.container.taskApplicationService.createTask(
                    in: spaceID,
                    actorID: actorID,
                    draft: draftState.taskDraft()
                )
                await appContext.homeViewModel.reload()
            case .project:
                _ = try await appContext.container.projectRepository.saveProject(
                    draftState.projectDraft(spaceID: spaceID)
                )
                await appContext.projectsViewModel.load()
            }

            focusedField = nil
            dismiss()
        } catch {
            isSaving = false
        }
    }
}

private enum ComposerCategory: Int, CaseIterable, Identifiable {
    case periodic
    case task
    case project

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .periodic:
            return "周期性"
        case .task:
            return "任务"
        case .project:
            return "项目"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .periodic:
            return "周期性标题"
        case .task:
            return "任务标题"
        case .project:
            return "项目标题"
        }
    }
}

private struct ComposerDraftState: Hashable {
    var category: ComposerCategory
    var title = ""
    var notes = ""
    var taskDate: Date
    var taskTime: Date?
    var periodicAnchorDate: Date
    var projectTargetDate: Date?
    var priority: ItemPriority = .normal
    var periodicReminderOffset: TimeInterval?
    var taskReminderOffset: TimeInterval?
    var projectReminderOffset: TimeInterval?
    var repeatRule: ItemRepeatRule

    init(initialCategory: ComposerCategory, referenceDate: Date) {
        self.category = initialCategory
        let calendar = Calendar.current
        self.taskDate = calendar.startOfDay(for: referenceDate)
        self.periodicAnchorDate = calendar.startOfDay(for: referenceDate)
        self.repeatRule = ItemRepeatRule(frequency: .daily)
    }

    var hasMeaningfulContent: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var taskDateText: String {
        taskDate.formatted(.dateTime.month(.defaultDigits).day())
    }

    var taskTimeText: String {
        guard let taskTime else { return "添加时间" }
        return taskTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var projectDateText: String {
        guard let projectTargetDate else { return "截止日期" }
        return projectTargetDate.formatted(.dateTime.month(.defaultDigits).day())
    }

    var repeatSummaryText: String {
        repeatRule.title(anchorDate: periodicAnchorDate, calendar: .current)
    }

    func reminderSummaryText(for category: ComposerCategory) -> String {
        let offset: TimeInterval?
        switch category {
        case .periodic:
            offset = periodicReminderOffset
        case .task:
            offset = taskReminderOffset
        case .project:
            offset = projectReminderOffset
        }

        guard let offset else { return "提醒" }
        return ReminderPreset.preset(for: offset)?.title ?? "提醒"
    }

    func taskDraft() -> TaskDraft {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch category {
        case .periodic:
            let anchorTime = Calendar.current.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: periodicAnchorDate
            ) ?? periodicAnchorDate
            let remindAt = periodicReminderOffset.map { anchorTime.addingTimeInterval(-$0) }
            return TaskDraft(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueAt: anchorTime,
                remindAt: remindAt,
                priority: priority,
                repeatRule: repeatRule
            )
        case .task:
            let mergedDate = taskTime.map { Self.merge(date: taskDate, timeSource: $0) }
            let fallbackDate = Calendar.current.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: taskDate
            ) ?? taskDate
            let dueAt = mergedDate ?? fallbackDate
            let remindAt = taskReminderOffset.map { dueAt.addingTimeInterval(-$0) }
            return TaskDraft(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueAt: dueAt,
                remindAt: remindAt,
                priority: priority
            )
        case .project:
            return TaskDraft(title: title, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        }
    }

    func projectDraft(spaceID: UUID) -> Project {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDate = projectTargetDate
        let remindAt = projectReminderOffset.flatMap { offset in
            targetDate?.addingTimeInterval(-offset)
        }

        return Project(
            id: UUID(),
            spaceID: spaceID,
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            colorToken: "graphite",
            status: .active,
            targetDate: targetDate,
            remindAt: remindAt,
            priority: priority,
            taskCount: 0,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil
        )
    }

    private static func merge(date: Date, timeSource: Date) -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeSource)
        return calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? date
    }
}

private struct ComposerPage: View {
    let category: ComposerCategory
    @Binding var draftState: ComposerDraftState
    @FocusState.Binding var focusedField: ComposerField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(category.titlePlaceholder, text: $draftState.title, axis: .vertical)
                .font(AppTheme.typography.sized(30, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(3)
                .focused($focusedField, equals: .title)

            TextField("添加备注...", text: $draftState.notes, axis: .vertical)
                .font(AppTheme.typography.sized(16, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.78))
                .lineLimit(8, reservesSpace: false)
                .focused($focusedField, equals: .notes)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ComposerChip: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let menu: ComposerMenu
}

private enum ComposerMenu: String, Identifiable {
    case date
    case time
    case reminder
    case priority
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(ComposerDateMenuDetent.self)]
        case .time:
            return [.fraction(0.46)]
        case .reminder, .priority, .repeatRule:
            return [.fraction(0.46)]
        }
    }
}

private struct ComposerDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            ComposerDatePickerSheet.preferredHeight + 12,
            context.maxDetentValue * 0.72
        )
    }
}

private struct ComposerMenuSheet: View {
    let menu: ComposerMenu
    @Binding var draftState: ComposerDraftState
    let onDismiss: () -> Void

    var body: some View {
        menuContent
            .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var menuContent: some View {
        switch menu {
        case .date:
            ComposerDatePickerSheet(draftState: $draftState, onDismiss: onDismiss)
        case .time:
            ComposerTimePickerSheet(draftState: $draftState)
        case .reminder:
            optionList(
                options: reminderMenuOptions,
                selectedTitle: draftState.reminderSummaryText(for: draftState.category)
            )
        case .priority:
            optionList(
                options: ItemPriority.allCases.map { priority in
                    ComposerOptionRow(
                        title: priority.title,
                        isSelected: draftState.priority == priority,
                        action: {
                            draftState.priority = priority
                            onDismiss()
                        }
                    )
                }
            )
        case .repeatRule:
            optionList(
                options: RepeatPreset.allCases.map { preset in
                    let title = preset.title(anchorDate: draftState.periodicAnchorDate)
                    return ComposerOptionRow(
                        title: title,
                        isSelected: title == draftState.repeatSummaryText,
                        action: {
                            draftState.repeatRule = preset.makeRule(anchorDate: draftState.periodicAnchorDate)
                            onDismiss()
                        }
                    )
                }
            )
        }
    }

    private var reminderMenuOptions: [ComposerOptionRow] {
        [ComposerOptionRow(title: "不提醒", isSelected: draftState.reminderSummaryText(for: draftState.category) == "提醒") {
            setReminder(nil)
        }] + ReminderPreset.allCases.map { preset in
            ComposerOptionRow(
                title: preset.title,
                isSelected: draftState.reminderSummaryText(for: draftState.category) == preset.title,
                action: {
                    setReminder(preset.secondsBeforeTarget)
                }
            )
        }
    }

    private func optionList(options: [ComposerOptionRow], selectedTitle: String? = nil) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button(action: option.action) {
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
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .modifier(ComposerMenuOptionGlassModifier())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear)
    }

    private func setReminder(_ seconds: TimeInterval?) {
        switch draftState.category {
        case .periodic:
            draftState.periodicReminderOffset = seconds
        case .task:
            draftState.taskReminderOffset = seconds
        case .project:
            draftState.projectReminderOffset = seconds
        }
        onDismiss()
    }
}

private struct ComposerDatePickerSheet: View {
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

    @Binding var draftState: ComposerDraftState
    let onDismiss: () -> Void
    @State private var displayedMonth: Date
    @State private var transitionDirection: CalendarMonthTransitionDirection = .forward

    init(draftState: Binding<ComposerDraftState>, onDismiss: @escaping () -> Void) {
        _draftState = draftState
        self.onDismiss = onDismiss

        let calendar = Calendar.current
        let initialDate: Date
        switch draftState.wrappedValue.category {
        case .periodic:
            initialDate = draftState.wrappedValue.periodicAnchorDate
        case .task:
            initialDate = draftState.wrappedValue.taskDate
        case .project:
            initialDate = draftState.wrappedValue.projectTargetDate ?? draftState.wrappedValue.taskDate
        }

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
        Array(
            repeating: GridItem(.flexible(), spacing: Self.gridColumnSpacing),
            count: 7
        )
    }

    private func headerHorizontalInset(for availableWidth: CGFloat) -> CGFloat {
        let gridWidth = max(availableWidth - (Self.horizontalPadding * 2), 0)
        let columnWidth = max((gridWidth - (Self.gridColumnSpacing * 6)) / 7, 0)
        let firstColumnCenterX = Self.horizontalPadding + (columnWidth / 2)
        let visualDayHalfWidth = min(widestDayLabelWidth, columnWidth) / 2

        // Keep the header aligned to the date glyph envelope rather than the raw
        // grid edge so month text and trailing controls track the first/last
        // visible day labels across device widths and font changes.
        return max(firstColumnCenterX - visualDayHalfWidth, Self.horizontalPadding)
    }

    private var selectedDate: Date {
        switch draftState.category {
        case .periodic:
            return draftState.periodicAnchorDate
        case .task:
            return draftState.taskDate
        case .project:
            return draftState.projectTargetDate ?? draftState.taskDate
        }
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

    private var calendarGridHeight: CGFloat {
        Self.calendarGridHeight
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

    private var monthCells: [CalendarDayCell] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [CalendarDayCell] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            cells.append(
                CalendarDayCell(
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
        triggerSelectionFeedback()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
    }

    private func selectDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        triggerSelectionFeedback()
        switch draftState.category {
        case .periodic:
            draftState.periodicAnchorDate = normalized
        case .task:
            draftState.taskDate = normalized
        case .project:
            draftState.projectTargetDate = normalized
        }
        onDismiss()
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayTextColor(for cell: CalendarDayCell) -> Color {
        if isSelected(cell.date) {
            return .white
        }
        if isToday(cell.date) {
            return AppTheme.colors.coral
        }
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.52)
    }

    private func triggerSelectionFeedback() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}

private struct ComposerTimePickerSheet: View {
    @Binding var draftState: ComposerDraftState
    @State private var selectedTime: Date
    @State private var scrollTempo: ComposerTimePickerScrollTempo = .idle
    @State private var numericCountsDown = false
    @State private var lastAppliedStep = 0
    @State private var isDragging = false
    @State private var lastDragSample: ComposerTimeDragSample?
    @State private var momentumTask: Task<Void, Never>?
    @State private var idleResetTask: Task<Void, Never>?
    @State private var hapticDriver = ComposerTimePickerHapticDriver()

    init(draftState: Binding<ComposerDraftState>) {
        _draftState = draftState
        let baseTime = draftState.wrappedValue.taskTime
            ?? Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: draftState.wrappedValue.taskDate)
            ?? draftState.wrappedValue.taskDate
        _selectedTime = State(initialValue: baseTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 26)

            Text("截止时间")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title.opacity(0.72))
                .padding(.bottom, 10)

            Text(displayedTime)
                .font(AppTheme.typography.sized(82, weight: .bold))
                .monospacedDigit()
                .tracking(-2.4)
                .foregroundStyle(AppTheme.colors.title)
                .contentTransition(.numericText(countsDown: numericCountsDown))
                .blur(radius: scrollTempo.blurRadius)
                .scaleEffect(scrollTempo.scale)
                .animation(.spring(response: 0.22, dampingFraction: 0.88), value: scrollTempo)
                .frame(height: 228)

            Spacer(minLength: 0)

            ComposerTimeVerticalHint(isVisible: scrollTempo == .idle)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(timeDragGesture)
        .onAppear {
            hapticDriver.prepare()
            writeBackSelectedTime()
        }
        .onChange(of: selectedTime) { _, _ in
            writeBackSelectedTime()
        }
        .onDisappear {
            momentumTask?.cancel()
            idleResetTask?.cancel()
        }
    }

    private var displayedTime: String {
        selectedTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func writeBackSelectedTime() {
        draftState.taskTime = selectedTime
    }

    private var timeDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                momentumTask?.cancel()
                momentumTask = nil

                let sample = ComposerTimeDragSample(
                    translation: value.translation.height,
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
                let velocity = currentVelocity(from: sample)
                let tempo = ComposerTimePickerScrollTempo.drag(for: velocity)
                lastDragSample = sample

                if !isDragging {
                    withAnimation(.easeOut(duration: 0.12)) {
                        isDragging = true
                    }
                }

                let step = Int((-value.translation.height / tempo.stepDistance).rounded())
                guard step != lastAppliedStep else { return }

                let delta = step - lastAppliedStep
                applyStepDelta(delta, tempo: tempo, hapticSource: .drag)
                lastAppliedStep = step
            }
            .onEnded { value in
                let finalSample = ComposerTimeDragSample(
                    translation: value.translation.height,
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
                let velocity = currentVelocity(from: finalSample)
                let tempo = ComposerTimePickerScrollTempo.drag(for: velocity)
                let momentumSteps = projectedMomentumSteps(from: value, tempo: tempo)

                lastAppliedStep = 0
                lastDragSample = nil
                withAnimation(.easeOut(duration: 0.16)) {
                    isDragging = false
                }

                if momentumSteps == 0 {
                    settle(after: tempo)
                } else {
                    startMomentum(steps: momentumSteps, tempo: tempo)
                }
            }
    }

    private func currentVelocity(from sample: ComposerTimeDragSample) -> CGFloat {
        guard let previous = lastDragSample else { return 0 }
        let deltaTime = max(sample.timestamp - previous.timestamp, 0.001)
        return abs((sample.translation - previous.translation) / deltaTime)
    }

    private func projectedMomentumSteps(from value: DragGesture.Value, tempo: ComposerTimePickerScrollTempo) -> Int {
        let projectedDelta = value.predictedEndTranslation.height - value.translation.height
        let projectedSteps = Int((-projectedDelta / (tempo.stepDistance * 1.1)).rounded())
        return max(-tempo.maxMomentumSteps, min(tempo.maxMomentumSteps, projectedSteps))
    }

    private func applyStepDelta(_ delta: Int, tempo: ComposerTimePickerScrollTempo, hapticSource: ComposerTimePickerHapticSource) {
        guard delta != 0 else { return }

        let updatedTime = Calendar.current.date(byAdding: .minute, value: delta * 5, to: selectedTime) ?? selectedTime

        scrollTempo = tempo
        numericCountsDown = delta < 0
        hapticDriver.emitDetents(count: abs(delta), tempo: tempo, source: hapticSource)

        withAnimation(tempo.textAnimation) {
            selectedTime = updatedTime
        }
    }

    private func startMomentum(steps: Int, tempo: ComposerTimePickerScrollTempo) {
        momentumTask?.cancel()
        momentumTask = Task { @MainActor in
            let direction = steps > 0 ? 1 : -1
            for _ in 0..<abs(steps) {
                guard !Task.isCancelled else { break }
                applyStepDelta(direction, tempo: tempo.momentumTempo, hapticSource: .momentum)
                try? await Task.sleep(for: .milliseconds(tempo.momentumTempo.detentIntervalMilliseconds))
            }
            settle(after: tempo.momentumTempo)
            momentumTask = nil
        }
    }

    private func settle(after tempo: ComposerTimePickerScrollTempo) {
        idleResetTask?.cancel()
        hapticDriver.emitSettle(for: tempo)
        idleResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            scrollTempo = .idle
        }
    }
}

private enum ComposerTimePickerScrollTempo: Equatable {
    case idle
    case dragSlow
    case dragMedium
    case dragFast
    case momentumSlow
    case momentumFast

    static func drag(for velocity: CGFloat) -> Self {
        switch velocity {
        case ..<220:
            return .dragSlow
        case ..<480:
            return .dragMedium
        default:
            return .dragFast
        }
    }

    var stepDistance: CGFloat {
        switch self {
        case .dragFast:
            return 12
        case .dragMedium:
            return 15
        case .dragSlow, .momentumSlow, .momentumFast, .idle:
            return 18
        }
    }

    var maxMomentumSteps: Int {
        switch self {
        case .dragFast:
            return 8
        case .dragMedium:
            return 5
        case .dragSlow, .momentumSlow, .momentumFast, .idle:
            return 2
        }
    }

    var momentumTempo: Self {
        switch self {
        case .dragFast, .momentumFast:
            return .momentumFast
        case .dragMedium, .dragSlow, .momentumSlow, .idle:
            return .momentumSlow
        }
    }

    var detentIntervalMilliseconds: Int {
        switch self {
        case .momentumFast:
            return 32
        case .momentumSlow:
            return 54
        default:
            return 0
        }
    }

    var blurRadius: CGFloat {
        switch self {
        case .dragFast, .momentumFast:
            return 1
        case .dragMedium, .momentumSlow:
            return 0.5
        case .dragSlow, .idle:
            return 0
        }
    }

    var scale: CGFloat {
        switch self {
        case .dragFast, .momentumFast:
            return 1.016
        case .dragMedium, .momentumSlow:
            return 1.008
        case .dragSlow, .idle:
            return 1
        }
    }

    var rollImpulse: CGFloat {
        switch self {
        case .dragFast, .momentumFast:
            return 18
        case .dragMedium, .momentumSlow:
            return 12
        case .dragSlow:
            return 8
        case .idle:
            return 0
        }
    }

    var textAnimation: Animation {
        switch self {
        case .dragFast, .momentumFast:
            return .linear(duration: 0.045)
        case .dragMedium, .momentumSlow:
            return .linear(duration: 0.075)
        case .dragSlow:
            return .spring(response: 0.18, dampingFraction: 0.9)
        case .idle:
            return .spring(response: 0.24, dampingFraction: 0.86)
        }
    }
}

private struct ComposerTimeDragSample {
    let translation: CGFloat
    let timestamp: TimeInterval
}

private enum ComposerTimePickerHapticSource {
    case drag
    case momentum
}

@MainActor
private final class ComposerTimePickerHapticDriver {
    #if canImport(UIKit)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private var detentCounter = 0
    #endif

    func prepare() {
        #if canImport(UIKit)
        selectionGenerator.prepare()
        softImpactGenerator.prepare()
        rigidImpactGenerator.prepare()
        #endif
    }

    func emitDetents(count: Int, tempo: ComposerTimePickerScrollTempo, source: ComposerTimePickerHapticSource) {
        #if canImport(UIKit)
        guard count > 0 else { return }

        for _ in 0..<count {
            detentCounter += 1
            selectionGenerator.selectionChanged()

            switch (tempo, source) {
            case (.dragMedium, .drag), (.momentumSlow, .momentum):
                if detentCounter.isMultiple(of: 2) {
                    softImpactGenerator.impactOccurred(intensity: 0.34)
                }
            case (.dragFast, .drag), (.momentumFast, .momentum):
                if detentCounter.isMultiple(of: 2) {
                    rigidImpactGenerator.impactOccurred(intensity: 0.42)
                }
            default:
                break
            }

            selectionGenerator.prepare()
            softImpactGenerator.prepare()
            rigidImpactGenerator.prepare()
        }
        #endif
    }

    func emitSettle(for tempo: ComposerTimePickerScrollTempo) {
        #if canImport(UIKit)
        switch tempo {
        case .dragFast, .momentumFast:
            rigidImpactGenerator.impactOccurred(intensity: 0.48)
        case .dragMedium, .momentumSlow:
            rigidImpactGenerator.impactOccurred(intensity: 0.38)
        case .dragSlow:
            softImpactGenerator.impactOccurred(intensity: 0.28)
        case .idle:
            break
        }
        detentCounter = 0
        prepare()
        #endif
    }
}

private struct ComposerTimeVerticalHint: View {
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up")
            Image(systemName: "arrow.down")
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.18))
        .opacity(isVisible ? 0.38 : 0)
        .modifier(ComposerSymbolHintEffectModifier(isActive: isVisible))
        .animation(.easeOut(duration: 0.16), value: isVisible)
    }
}

private struct ComposerSymbolHintEffectModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.symbolEffect(.pulse, options: .repeating, isActive: isActive)
        } else {
            content
        }
    }
}

private struct ComposerOptionRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private enum ReminderPreset: CaseIterable, Identifiable {
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

    static func preset(for secondsBeforeTarget: TimeInterval) -> ReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

private enum RepeatPreset: CaseIterable, Identifiable {
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

private struct ComposerChipSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1)
            }
    }
}

private struct ComposerMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private enum ComposerField: Hashable {
    case title
    case notes
}

private struct CalendarDayCell: Identifiable {
    let id = UUID()
    let date: Date
    let isInDisplayedMonth: Bool
}

private enum CalendarMonthTransitionDirection {
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

private struct ComposerMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .presentationSizing(.page)
        } else {
            content
        }
    }
}
