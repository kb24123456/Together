import SwiftUI
#if canImport(UIKit)
import Combine
import UIKit
import CoreText
#endif

enum TaskEditorMenu: String, Identifiable {
    case date
    case time
    case reminder
    case repeatRule
    case subtasks
    case template

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .date:
            return "calendar"
        case .time:
            return "clock"
        case .reminder:
            return "bell"
        case .repeatRule:
            return "arrow.triangle.2.circlepath"
        case .subtasks:
            return "checklist"
        case .template:
            return "bookmark"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .date:
            return "日期"
        case .time:
            return "时间"
        case .reminder:
            return "提醒"
        case .repeatRule:
            return "重复"
        case .subtasks:
            return "子任务"
        case .template:
            return "模板"
        }
    }
}

enum TaskEditorMenuContext: Equatable {
    case templates
    case task
    case project

    var menus: [TaskEditorMenu] {
        switch self {
        case .task:
            return [.date, .time, .reminder, .repeatRule]
        case .project:
            return [.date, .subtasks]
        case .templates:
            return [.template]
        }
    }

    var detents: Set<PresentationDetent> {
        [.height(unifiedPresentationHeight)]
    }

    private var unifiedPresentationHeight: CGFloat {
        switch self {
        case .task:
            return TaskEditorTimePickerSheet.preferredHeight(
                showsQuickPresets: true,
                showsPrimaryButton: false
            ) + TaskEditorUnifiedMenuMetrics.sheetChromeHeight
        case .project:
            return max(
                TaskEditorDatePickerSheet.preferredHeight,
                492
            ) + TaskEditorUnifiedMenuMetrics.sheetChromeHeight
        case .templates:
            return 440
        }
    }
}

private struct TaskEditorTemplateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(440, context.maxDetentValue * 0.72)
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
    case repeatRule(title: String, rank: Int)
    case subtasks(Int)

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
        case let (.repeatRule(_, oldRank), .repeatRule(_, newRank)):
            return newRank >= oldRank ? .up : .down
        case let (.subtasks(oldCount), .subtasks(newCount)):
            return newCount >= oldCount ? .up : .down
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

struct TaskEditorStagedReminderContext: Equatable {
    let selectedDate: Date
    let selectedTime: Date?
    let reminderOffset: TimeInterval?

    var hasExplicitTime: Bool {
        selectedTime != nil
    }

    var isReminderMenuDisabled: Bool {
        selectedTime == nil
    }

    var reminderTargetDate: Date {
        let calendar = Calendar.current
        guard let selectedTime else {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        }

        let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        return calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? selectedDate
    }

    var remindAt: Date? {
        reminderOffset.map { reminderTargetDate.addingTimeInterval(-$0) }
    }
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
                                TaskEditorAnimatedChipIcon(
                                    systemImage: chip.systemImage,
                                    menu: chip.menu,
                                    semanticValue: chip.semanticValue,
                                    font: AppTheme.typography.sized(14, weight: .semibold)
                                )

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
                        .buttonStyle(TaskEditorChipButtonStyle())

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
    var usesGlassBackground = true

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
                    .modifier(TaskEditorMenuOptionSurfaceModifier(isEnabled: usesGlassBackground))
                }
            }
            .padding(TaskEditorMenuOptionMetrics.outerInset)
        }
        .scrollIndicators(.hidden)
        .background(.clear)
    }
}

extension TaskEditorOptionList {
    static func preferredHeight(optionCount: Int) -> CGFloat {
        let clampedCount = max(optionCount, 1)
        let rowsHeight = CGFloat(clampedCount) * TaskEditorMenuOptionMetrics.height
        let spacingHeight = CGFloat(max(clampedCount - 1, 0)) * 10
        let verticalPadding = TaskEditorMenuOptionMetrics.outerInset * 2
        return rowsHeight + spacingHeight + verticalPadding
    }
}

struct TaskEditorReminderOptionList: View {
    let selectedOffset: TimeInterval?
    let selectionFeedback: () -> Void
    let onSelect: (TimeInterval?) -> Void

    @State private var isCustomExpanded = false
    @State private var customValue: Int = 10
    @State private var customUnit: CustomReminderUnit = .minutes

    enum CustomReminderUnit: String, CaseIterable {
        case minutes = "分钟"
        case hours = "小时"
        case days = "天"

        var secondsPerUnit: TimeInterval {
            switch self {
            case .minutes: return 60
            case .hours: return 3600
            case .days: return 86400
            }
        }
    }

    private var isCustomSelected: Bool {
        guard let offset = selectedOffset else { return false }
        return TaskEditorReminderPreset.preset(for: offset) == nil && offset > 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    optionButton(title: "不提醒", isSelected: selectedOffset == nil) {
                        onSelect(nil)
                    }

                    ForEach(TaskEditorReminderPreset.allCases) { preset in
                        optionButton(title: preset.title, isSelected: selectedOffset == preset.secondsBeforeTarget) {
                            onSelect(preset.secondsBeforeTarget)
                        }
                    }

                    // Custom option
                    VStack(spacing: 0) {
                        Button {
                            selectionFeedback()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isCustomExpanded.toggle()
                            }
                            if isCustomExpanded {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                                        proxy.scrollTo("custom-bottom", anchor: .bottom)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("自定义")
                                    .font(AppTheme.typography.sized(17, weight: .semibold))
                                    .foregroundStyle(AppTheme.colors.title)
                                Spacer(minLength: 0)
                                if isCustomSelected {
                                    Image(systemName: "checkmark")
                                        .font(AppTheme.typography.sized(14, weight: .bold))
                                        .foregroundStyle(AppTheme.colors.coral)
                                }
                                Image(systemName: "chevron.down")
                                    .font(AppTheme.typography.sized(12, weight: .semibold))
                                    .foregroundStyle(AppTheme.colors.body.opacity(0.4))
                                    .rotationEffect(.degrees(isCustomExpanded ? 180 : 0))
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
                        .buttonStyle(TaskEditorMenuOptionButtonStyle())

                        if isCustomExpanded {
                            customPickerRow
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .id("custom-bottom")
                        }
                    }
                    .background(
                        RoundedRectangle(
                            cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                            style: .continuous
                        )
                        .fill(AppTheme.colors.surfaceElevated.opacity(0.6))
                    )
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isCustomExpanded)
                }
                .padding(TaskEditorMenuOptionMetrics.outerInset)
            }
            .scrollIndicators(.hidden)
            .background(.clear)
        }
    }

    private func optionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            selectionFeedback()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Spacer(minLength: 0)
                if isSelected {
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
        .background(
            RoundedRectangle(
                cornerRadius: TaskEditorMenuOptionMetrics.cornerRadius,
                style: .continuous
            )
            .fill(AppTheme.colors.surfaceElevated.opacity(0.6))
        )
    }

    private var customPickerRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button {
                    selectionFeedback()
                    customValue = max(1, customValue - 1)
                    applyCustomValue()
                } label: {
                    Image(systemName: "minus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.colors.body.opacity(0.7))

                Text("\(customValue)")
                    .font(AppTheme.typography.sized(20, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(minWidth: 36)
                    .contentTransition(.numericText(value: Double(customValue)))
                    .animation(.snappy(duration: 0.2), value: customValue)

                Button {
                    selectionFeedback()
                    customValue = min(99, customValue + 1)
                    applyCustomValue()
                } label: {
                    Image(systemName: "plus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.colors.body.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )

            HStack(spacing: 6) {
                ForEach(CustomReminderUnit.allCases, id: \.rawValue) { unit in
                    Button {
                        selectionFeedback()
                        customUnit = unit
                        applyCustomValue()
                    } label: {
                        Text(unit.rawValue)
                            .font(AppTheme.typography.sized(14, weight: .semibold))
                            .foregroundStyle(customUnit == unit ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.5))
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(customUnit == unit ? AppTheme.colors.pillSurface : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func applyCustomValue() {
        let seconds = TimeInterval(customValue) * customUnit.secondsPerUnit
        onSelect(seconds)
    }
}

private struct TaskEditorMenuOptionSurfaceModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(TaskEditorMenuOptionGlassModifier())
        } else {
            content
        }
    }
}

struct TaskEditorSettingsSheet<Content: View>: View {
    let title: String
    let menus: [TaskEditorMenu]
    @Binding var activeMenu: TaskEditorMenu
    let disabledMenus: Set<TaskEditorMenu>
    let selectionFeedback: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let onMenuTap: ((TaskEditorMenu) -> Bool)?
    let titleTrailingAccessory: AnyView?
    let menuPresentation: (TaskEditorMenu) -> TaskEditorMenuSwitcherPresentation
    @ViewBuilder let content: (TaskEditorMenu) -> Content

    @State private var displayedMenu: TaskEditorMenu
    @State private var transitionDirection: TaskEditorMenuTransitionDirection = .forward

    init(
        title: String,
        menus: [TaskEditorMenu],
        activeMenu: Binding<TaskEditorMenu>,
        disabledMenus: Set<TaskEditorMenu> = [],
        selectionFeedback: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        onMenuTap: ((TaskEditorMenu) -> Bool)? = nil,
        titleTrailingAccessory: AnyView? = nil,
        menuPresentation: @escaping (TaskEditorMenu) -> TaskEditorMenuSwitcherPresentation = {
            .icon(systemImage: $0.systemImage, accessibilityTitle: $0.accessibilityTitle)
        },
        @ViewBuilder content: @escaping (TaskEditorMenu) -> Content
    ) {
        self.title = title
        self.menus = menus
        _activeMenu = activeMenu
        self.disabledMenus = disabledMenus
        self.selectionFeedback = selectionFeedback
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onMenuTap = onMenuTap
        self.titleTrailingAccessory = titleTrailingAccessory
        self.menuPresentation = menuPresentation
        self.content = content
        _displayedMenu = State(initialValue: activeMenu.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ZStack {
                content(displayedMenu)
                    .id(displayedMenu.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(menuTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

            TaskEditorMenuSwitcher(
                menus: menus,
                activeMenu: activeMenu,
                disabledMenus: disabledMenus,
                presentation: menuPresentation
            ) { nextMenu in
                if onMenuTap?(nextMenu) == true { return }
                guard nextMenu != activeMenu else { return }
                guard disabledMenus.contains(nextMenu) == false else { return }
                transitionDirection = transitionDirectionForMenuChange(to: nextMenu)
                selectionFeedback()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    activeMenu = nextMenu
                    displayedMenu = nextMenu
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: activeMenu) { oldValue, newValue in
            guard oldValue != newValue else { return }
            transitionDirection = transitionDirectionForMenuChange(to: newValue)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                displayedMenu = newValue
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TaskEditorSettingsHeaderButton(title: "取消", action: onCancel)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Text(title)
                    .font(AppTheme.typography.sized(24, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .contentTransition(.numericText())

                if let titleTrailingAccessory {
                    titleTrailingAccessory
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }

            Spacer(minLength: 0)

            TaskEditorSettingsHeaderButton(title: "确定", action: onConfirm, isTrailing: true)
        }
        .frame(minHeight: 48)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: title)
    }

    private var menuTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection.insertionEdge).combined(with: .opacity),
            removal: .move(edge: transitionDirection.removalEdge).combined(with: .opacity)
        )
    }

    private func transitionDirectionForMenuChange(to nextMenu: TaskEditorMenu) -> TaskEditorMenuTransitionDirection {
        let currentIndex = menus.firstIndex(of: displayedMenu) ?? 0
        let nextIndex = menus.firstIndex(of: nextMenu) ?? currentIndex
        return nextIndex >= currentIndex ? .forward : .backward
    }
}

private struct TaskEditorSettingsHeaderButton: View {
    let title: String
    let action: () -> Void
    var isTrailing = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.sized(19, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: 72, alignment: isTrailing ? .trailing : .leading)
                .frame(height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TaskEditorSettingsPresentationBackground: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.46), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                }
        }
    }
}

struct TaskEditorUnifiedMenuSheet<Content: View>: View {
    let context: TaskEditorMenuContext
    @Binding var activeMenu: TaskEditorMenu
    let disabledMenus: Set<TaskEditorMenu>
    let selectionFeedback: () -> Void
    let headerTitle: String?
    let switcherPlacement: TaskEditorMenuSwitcherPlacement
    let onClose: () -> Void
    let onSave: (() -> Void)?
    @ViewBuilder let content: (TaskEditorMenu) -> Content

    @State private var displayedMenu: TaskEditorMenu
    @State private var transitionDirection: TaskEditorMenuTransitionDirection = .forward

    init(
        context: TaskEditorMenuContext,
        activeMenu: Binding<TaskEditorMenu>,
        disabledMenus: Set<TaskEditorMenu> = [],
        selectionFeedback: @escaping () -> Void,
        headerTitle: String? = nil,
        switcherPlacement: TaskEditorMenuSwitcherPlacement = .top,
        onClose: @escaping () -> Void = {},
        onSave: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (TaskEditorMenu) -> Content
    ) {
        self.context = context
        _activeMenu = activeMenu
        self.disabledMenus = disabledMenus
        self.selectionFeedback = selectionFeedback
        self.headerTitle = headerTitle
        self.switcherPlacement = switcherPlacement
        self.onClose = onClose
        self.onSave = onSave
        self.content = content
        _displayedMenu = State(initialValue: activeMenu.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if headerTitle == nil, switcherPlacement == .top {
                switcherView
            }

            ZStack {
                content(displayedMenu)
                    .id(displayedMenu.id)
                    .transition(menuTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

            if headerTitle == nil, switcherPlacement == .bottom {
                switcherView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: activeMenu) { oldValue, newValue in
            guard oldValue != newValue else { return }
            transitionDirection = transitionDirectionForMenuChange(to: newValue)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                displayedMenu = newValue
            }
        }
    }

    private var menuTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection.insertionEdge).combined(with: .opacity),
            removal: .move(edge: transitionDirection.removalEdge).combined(with: .opacity)
        )
    }

    private func transitionDirectionForMenuChange(to nextMenu: TaskEditorMenu) -> TaskEditorMenuTransitionDirection {
        let menus = context.menus
        let currentIndex = menus.firstIndex(of: displayedMenu) ?? 0
        let nextIndex = menus.firstIndex(of: nextMenu) ?? currentIndex
        return nextIndex >= currentIndex ? .forward : .backward
    }

    private var switcherView: some View {
        TaskEditorMenuSwitcher(
            menus: context.menus,
            activeMenu: activeMenu,
            disabledMenus: disabledMenus,
            presentation: { menu in
                .icon(systemImage: menu.systemImage, accessibilityTitle: menu.accessibilityTitle)
            },
            onSelect: { nextMenu in
                guard nextMenu != activeMenu else { return }
                guard disabledMenus.contains(nextMenu) == false else { return }
                transitionDirection = transitionDirectionForMenuChange(to: nextMenu)
                selectionFeedback()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    activeMenu = nextMenu
                    displayedMenu = nextMenu
                }
            }
        )
        .padding(.horizontal, 18)
        .padding(.top, switcherPlacement == .bottom ? 0 : 14)
        .padding(.bottom, switcherPlacement == .bottom ? 10 : 10)
    }

    private var currentTitle: String {
        headerTitle ?? displayedMenu.accessibilityTitle
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            topBarButton(systemImage: "xmark", accessibilityLabel: "关闭", action: onClose)

            Spacer(minLength: 0)

            titleView

            Spacer(minLength: 0)

            topBarButton(
                systemImage: "checkmark",
                accessibilityLabel: "保存",
                action: {
                    onSave?()
                }
            )
            .opacity(onSave == nil ? 0.35 : 1)
            .allowsHitTesting(onSave != nil)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var titleView: some View {
        ZStack {
            Text(currentTitle)
                .id(currentTitle)
                .font(AppTheme.typography.sized(18, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .animation(.easeInOut(duration: 0.22), value: currentTitle)
    }

    private func topBarButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(16, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

enum TaskEditorMenuSwitcherPlacement {
    case top
    case bottom
}

private enum TaskEditorMenuTransitionDirection {
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

struct TaskEditorMenuSwitcherPresentation: Equatable {
    let systemImage: String?
    let title: String?
    let accessibilityTitle: String

    static func icon(systemImage: String, accessibilityTitle: String) -> Self {
        .init(systemImage: systemImage, title: nil, accessibilityTitle: accessibilityTitle)
    }

    static func title(_ title: String, accessibilityTitle: String) -> Self {
        .init(systemImage: nil, title: title, accessibilityTitle: accessibilityTitle)
    }
}

private struct TaskEditorMenuSwitcher: View {
    let menus: [TaskEditorMenu]
    let activeMenu: TaskEditorMenu
    let disabledMenus: Set<TaskEditorMenu>
    let presentation: (TaskEditorMenu) -> TaskEditorMenuSwitcherPresentation
    let onSelect: (TaskEditorMenu) -> Void

    @State private var rotateTrigger = 0
    @State private var wiggleTrigger = 0
    @State private var lastRotatedMenu: TaskEditorMenu? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(menus) { menu in
                let itemPresentation = presentation(menu)
                Button {
                    triggerSymbolEffect(for: menu)
                    onSelect(menu)
                } label: {
                    ZStack {
                        if let systemImage = itemPresentation.systemImage {
                            Image(systemName: systemImage)
                                .font(AppTheme.typography.sized(18, weight: .semibold))
                                .transition(.opacity.combined(with: .scale(scale: 0.88)))
                                .symbolEffect(
                                    .rotate.byLayer,
                                    options: .nonRepeating,
                                    value: menu == lastRotatedMenu ? rotateTrigger : 0
                                )
                                .symbolEffect(
                                    .wiggle.byLayer,
                                    options: .nonRepeating,
                                    value: menu == .reminder ? wiggleTrigger : 0
                                )
                        }

                        if let title = itemPresentation.title {
                            Text(title)
                                .font(AppTheme.typography.sized(16, weight: .bold))
                                .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        }
                    }
                    .foregroundStyle(foregroundColor(for: menu))
                    .frame(maxWidth: .infinity)
                    .frame(height: TaskEditorToolbarMetrics.itemHeight)
                    .background {
                        if activeMenu == menu {
                            Capsule(style: .continuous)
                                .fill(AppTheme.colors.pillSurface)
                        }
                    }
                    .overlay {
                        if activeMenu == menu {
                            Capsule(style: .continuous)
                                .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: itemPresentation)
                }
                .buttonStyle(.plain)
                .disabled(disabledMenus.contains(menu))
                .opacity(disabledMenus.contains(menu) ? 0.34 : 1)
                .accessibilityLabel(itemPresentation.accessibilityTitle)
            }
        }
    }

    private func triggerSymbolEffect(for menu: TaskEditorMenu) {
        switch menu {
        case .time, .repeatRule:
            lastRotatedMenu = menu
            rotateTrigger += 1
        case .reminder:
            wiggleTrigger += 1
        default:
            break
        }
    }

    private func foregroundColor(for menu: TaskEditorMenu) -> Color {
        if disabledMenus.contains(menu) {
            return AppTheme.colors.body.opacity(0.35)
        }
        return activeMenu == menu ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.72)
    }
}

enum TaskEditorToolbarMetrics {
    static let itemHeight: CGFloat = 48
}

struct TaskEditorDatePickerSheet: View {
    static let gridRowHeight: CGFloat = 36
    static let gridRowSpacing: CGFloat = 6
    static let sixWeekGridRowSpacing: CGFloat = 4
    static let gridColumnSpacing: CGFloat = 0
    static let weekdayRowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 36
    static let horizontalPadding: CGFloat = 8
    static let topPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 0
    static let contentSpacing: CGFloat = 6
    static let headerToGridSpacing: CGFloat = 6
    static let calendarGridHeight: CGFloat = (gridRowHeight * 5) + (gridRowSpacing * 4)
    static let preferredHeight: CGFloat =
        topPadding + bottomPadding + headerHeight + headerToGridSpacing + weekdayRowHeight + contentSpacing + calendarGridHeight

    @Binding var selectedDate: Date
    let selectionFeedback: () -> Void
    let onDismiss: () -> Void
    let dismissesOnSelection: Bool
    @State private var displayedMonth: Date
    @State private var transitionDirection: TaskEditorMonthTransitionDirection = .forward

    init(
        selectedDate: Binding<Date>,
        selectionFeedback: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        dismissesOnSelection: Bool = true
    ) {
        _selectedDate = selectedDate
        self.selectionFeedback = selectionFeedback
        self.onDismiss = onDismiss
        self.dismissesOnSelection = dismissesOnSelection
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
                HStack(spacing: 8) {
                    Text(monthTitle)
                        .font(AppTheme.typography.sized(20, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)
                        .contentTransition(.numericText())

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        calendarButton(systemName: "chevron.left") {
                            shiftMonth(by: -1)
                        }

                        Button("Today") {
                            let today = Date()
                            selectionFeedback()
                            displayedMonth = monthStart(for: today)
                            selectDate(today)
                        }
                        .buttonStyle(.plain)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(minWidth: 76, minHeight: 40)
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

                    ZStack {
                        monthGrid
                    }
                    .frame(height: Self.calendarGridHeight, alignment: .top)
                    .clipped()
                    .animation(.spring(response: 0.34, dampingFraction: 0.88), value: displayedMonth)
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
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

    private var monthGrid: some View {
        let metrics = monthGridMetrics

        return LazyVGrid(columns: calendarColumns, spacing: metrics.rowSpacing) {
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
                            .font(AppTheme.typography.sized(metrics.dayFontSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(dayTextColor(for: cell))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.rowHeight)
                }
                .buttonStyle(.plain)
            }
        }
        .id(monthIdentity)
        .transition(monthTransition)
    }

    private var monthGridMetrics: TaskEditorDatePickerMonthGridMetrics {
        let weekCount = max(monthCells.count / 7, 1)
        guard weekCount > 5 else {
            return TaskEditorDatePickerMonthGridMetrics(
                rowHeight: Self.gridRowHeight,
                rowSpacing: Self.gridRowSpacing,
                dayFontSize: 18
            )
        }

        let rowSpacing = Self.sixWeekGridRowSpacing
        let rowHeight = max(
            (Self.calendarGridHeight - (rowSpacing * CGFloat(weekCount - 1))) / CGFloat(weekCount),
            28
        )

        return TaskEditorDatePickerMonthGridMetrics(
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            dayFontSize: 16
        )
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

    private func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        if dismissesOnSelection {
            onDismiss()
        }
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
    let showsQuickPresets: Bool
    let savesOnQuickPresetSelection: Bool
    let showsPrimaryButton: Bool
    let primaryButtonTitle: String
    let selectionFeedback: () -> Void
    let primaryFeedback: () -> Void
    let onTimeSaved: (() -> Void)?
    let onDismiss: () -> Void
    @State private var stagedTime: Date

    init(
        selectedTime: Binding<Date?>,
        anchorDate: Date,
        quickPresetMinutes: [Int],
        showsQuickPresets: Bool = true,
        savesOnQuickPresetSelection: Bool = true,
        showsPrimaryButton: Bool = true,
        primaryButtonTitle: String = "添加",
        selectionFeedback: @escaping () -> Void,
        primaryFeedback: @escaping () -> Void,
        onTimeSaved: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        _selectedTime = selectedTime
        self.anchorDate = anchorDate
        self.quickPresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(quickPresetMinutes)
        self.showsQuickPresets = showsQuickPresets
        self.savesOnQuickPresetSelection = savesOnQuickPresetSelection
        self.showsPrimaryButton = showsPrimaryButton
        self.primaryButtonTitle = primaryButtonTitle
        self.selectionFeedback = selectionFeedback
        self.primaryFeedback = primaryFeedback
        self.onTimeSaved = onTimeSaved
        self.onDismiss = onDismiss
        let baseTime = selectedTime.wrappedValue
            ?? Self.roundedTimeSeed(for: anchorDate)
            ?? anchorDate
        _stagedTime = State(initialValue: baseTime)
    }

    var body: some View {
        GeometryReader { proxy in
            let pickerHeight = adaptivePickerHeight(for: proxy.size.height)

            VStack(spacing: 0) {
                if showsQuickPresets {
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
                                    .frame(minHeight: 48)
                            }
                            .buttonStyle(TaskEditorMenuOptionButtonStyle())
                            .modifier(TaskEditorMenuOptionGlassModifier())
                        }
                    }
                    .padding(.top, TaskEditorTimePickerMetrics.verticalInset)
                    .padding(.horizontal, TaskEditorMenuOptionMetrics.outerInset)
                    .padding(.bottom, TaskEditorTimePickerMetrics.contentSpacing)
                }

                TaskEditorSingleColumnTimeWheel(
                    selection: $stagedTime,
                    minuteInterval: 5
                )
                .frame(maxWidth: .infinity)
                .frame(height: pickerHeight)
                .clipped()
                .padding(.top, showsQuickPresets ? 0 : TaskEditorTimePickerMetrics.verticalInset)
                .padding(.bottom, TaskEditorTimePickerMetrics.contentSpacing)

                if showsPrimaryButton {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onChange(of: stagedTime) { oldValue, newValue in
            guard showsPrimaryButton == false, oldValue != newValue else { return }
            selectedTime = newValue
        }
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
        if savesOnQuickPresetSelection {
            saveSelection(presetTime)
        }
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }

    private func adaptivePickerHeight(for availableHeight: CGFloat) -> CGFloat {
        let presetBlockHeight =
            showsQuickPresets
            ? (TaskEditorTimePickerMetrics.verticalInset + 48 + TaskEditorTimePickerMetrics.contentSpacing)
            : 0
        let bottomBlockHeight =
            showsPrimaryButton
            ? (
                TaskEditorMenuOptionMetrics.height
                + TaskEditorTimePickerMetrics.verticalInset
                + TaskEditorTimePickerMetrics.contentSpacing
            )
            : TaskEditorTimePickerMetrics.verticalInset
        let topInset = showsQuickPresets ? 0 : TaskEditorTimePickerMetrics.verticalInset
        let availablePickerHeight = availableHeight - presetBlockHeight - bottomBlockHeight - topInset

        return min(
            max(availablePickerHeight, TaskEditorTimePickerMetrics.minimumPickerHeight),
            TaskEditorTimePickerMetrics.pickerHeight
        )
    }

    private func saveSelection(_ value: Date? = nil) {
        selectedTime = value ?? stagedTime
        onTimeSaved?()
        onDismiss()
    }
}

extension TaskEditorTimePickerSheet {
    static func preferredHeight(
        showsQuickPresets: Bool = true,
        showsPrimaryButton: Bool = false
    ) -> CGFloat {
        let presetBlockHeight =
            showsQuickPresets
            ? (TaskEditorTimePickerMetrics.verticalInset + 48 + TaskEditorTimePickerMetrics.contentSpacing)
            : 0
        let topInset = showsQuickPresets ? 0 : TaskEditorTimePickerMetrics.verticalInset
        let pickerBlockHeight = TaskEditorTimePickerMetrics.pickerHeight + TaskEditorTimePickerMetrics.contentSpacing
        let bottomBlockHeight =
            showsPrimaryButton
            ? (
                TaskEditorMenuOptionMetrics.height
                + TaskEditorTimePickerMetrics.verticalInset
                + TaskEditorTimePickerMetrics.contentSpacing
            )
            : TaskEditorTimePickerMetrics.verticalInset

        return presetBlockHeight + topInset + pickerBlockHeight + bottomBlockHeight
    }
}

struct TaskEditorSettingsTimePage: View {
    @Binding var selectedTime: Date?
    @Binding var isAllDay: Bool
    let anchorDate: Date
    @Binding var selectedDate: Date
    let selectionFeedback: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TaskEditorCenteredWeekDatePicker(
                selectedDate: $selectedDate,
                selectionFeedback: selectionFeedback
            )
            .frame(height: 92)

            GeometryReader { proxy in
                TaskEditorSingleColumnTimeWheel(
                    selection: wheelSelection,
                    minuteInterval: 5,
                    selectionCapsuleFill: AppTheme.colors.surfaceElevated.opacity(0.92),
                    showsSelectionIcon: true
                )
                .frame(maxWidth: .infinity, maxHeight: max(proxy.size.height, 0))
                .opacity(isAllDay ? 0.3 : 1)
                .allowsHitTesting(!isAllDay)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wheelSelection: Binding<Date> {
        Binding(
            get: { selectedTime ?? defaultTime },
            set: { newValue in
                selectedTime = newValue
                if isAllDay {
                    isAllDay = false
                }
            }
        )
    }

    private var defaultTime: Date {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        let roundedMinute = Int((Double(minute) / 5).rounded()) * 5
        let minuteOverflow = roundedMinute / 60
        let normalizedMinute = roundedMinute % 60
        let normalizedHour = (hour + minuteOverflow) % 24

        return calendar.date(
            bySettingHour: normalizedHour,
            minute: normalizedMinute,
            second: 0,
            of: anchorDate
        ) ?? anchorDate
    }

}

struct TaskEditorCenteredWeekDatePicker: View {
    @Binding var selectedDate: Date
    let selectionFeedback: () -> Void

    @State private var weekPagerOffset: CGFloat = 0
    @State private var isWeekPagerSettling = false

    private let calendar = Calendar.current
    private let weekPageBreathingGap: CGFloat = 0
    private let weekDateSpacing: CGFloat = AppTheme.spacing.sm

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)

            HStack(spacing: 0) {
                ForEach([-1, 0, 1], id: \.self) { offset in
                    weekPage(for: offset)
                        .frame(width: pageWidth - weekPageBreathingGap)
                        .frame(width: pageWidth)
                        .opacity(weekPageOpacity(for: offset, pageWidth: pageWidth))
                }
            }
            .frame(width: pageWidth * 3, alignment: .leading)
            .offset(x: -pageWidth + weekPagerOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(weekPagerDragGesture(pageWidth: pageWidth))
        }
        .frame(height: 96)
        .clipped()
    }

    private func weekPage(for offset: Int) -> some View {
        HStack(spacing: weekDateSpacing) {
            ForEach(centeredDates(shiftedByWeeks: offset), id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                Button {
                    guard !isSelected else { return }
                    selectionFeedback()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                        selectedDate = date
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(weekdayLabel(for: date))
                            .font(AppTheme.typography.sized(13, weight: .semibold))
                            .foregroundStyle(isSelected ? AppTheme.colors.coral : AppTheme.colors.textTertiary)

                        Text(date, format: .dateTime.day())
                            .font(
                                AppTheme.typography.sized(
                                    isSelected ? 24 : 21,
                                    weight: isSelected ? .bold : .semibold
                                )
                            )
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.title
                                : AppTheme.colors.body.opacity(0.58)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(AppTheme.colors.pillSurface)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isSelected ? AppTheme.colors.pillOutline : AppTheme.colors.outline.opacity(0.08),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
    }

    private func centeredDates(shiftedByWeeks offset: Int) -> [Date] {
        let centerDate = calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) ?? selectedDate
        return (-3...3).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: centerDate))
        }
    }

    private func weekPageOpacity(for offset: Int, pageWidth: CGFloat) -> Double {
        let relativeOffset = (CGFloat(offset) * pageWidth + weekPagerOffset) / pageWidth
        let distance = min(abs(relativeOffset), 1)
        return 1 - Double(distance) * 0.28
    }

    private func weekPagerDragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !isWeekPagerSettling else { return }
                weekPagerOffset = resistedWeekPagerOffset(for: value.translation.width, pageWidth: pageWidth)
            }
            .onEnded { value in
                guard !isWeekPagerSettling else { return }
                let predicted = value.predictedEndTranslation.width
                let threshold = pageWidth * 0.18

                let direction: Int
                if predicted <= -threshold {
                    direction = 1
                } else if predicted >= threshold {
                    direction = -1
                } else {
                    direction = 0
                }

                settleWeekPager(to: direction, pageWidth: pageWidth)
            }
    }

    private func resistedWeekPagerOffset(for translation: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let progress = min(abs(translation) / max(pageWidth, 1), 1)
        let resistance = 1 - (progress * 0.22)
        return translation * resistance
    }

    private func settleWeekPager(to direction: Int, pageWidth: CGFloat) {
        isWeekPagerSettling = true
        let targetOffset = CGFloat(-direction) * pageWidth

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            weekPagerOffset = targetOffset
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            if direction != 0 {
                selectionFeedback()
                selectedDate = calendar.date(byAdding: .day, value: direction * 7, to: selectedDate) ?? selectedDate
            }
            weekPagerOffset = 0
            isWeekPagerSettling = false
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return ""
        }
    }
}

struct TaskEditorSettingsMonthPage: View {
    @Binding var selectedDate: Date
    let selectionFeedback: () -> Void
    var onDaySelection: ((Date) -> Void)? = nil

    @State private var displayedMonth: Date
    @State private var transitionDirection: TaskEditorMonthTransitionDirection = .forward

    init(
        selectedDate: Binding<Date>,
        selectionFeedback: @escaping () -> Void,
        onDaySelection: ((Date) -> Void)? = nil
    ) {
        _selectedDate = selectedDate
        self.selectionFeedback = selectionFeedback
        self.onDaySelection = onDaySelection
        let calendar = Calendar.current
        let initialDate = selectedDate.wrappedValue
        _displayedMonth = State(
            initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: calendarColumns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.46))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
            }

            ZStack {
                monthGrid
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(monthDragGesture)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedDate) { _, newValue in
            let month = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: newValue)
            ) ?? newValue
            if Calendar.current.isDate(month, equalTo: displayedMonth, toGranularity: .month) == false {
                displayedMonth = month
            }
        }
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    }

    private var weekdaySymbols: [String] { ["日", "一", "二", "三", "四", "五", "六"] }

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

    private var monthGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 8) {
            ForEach(monthCells) { cell in
                Button {
                    selectionFeedback()
                    let nextDate = Calendar.current.startOfDay(for: cell.date)
                    selectedDate = nextDate
                    onDaySelection?(nextDate)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isSelected(cell.date) ? AppTheme.colors.coral : .clear)
                            .overlay {
                                Circle()
                                    .stroke(isToday(cell.date) && !isSelected(cell.date) ? AppTheme.colors.coral : .clear, lineWidth: 1.8)
                            }

                        Text("\(Calendar.current.component(.day, from: cell.date))")
                            .font(AppTheme.typography.sized(18, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(dayTextColor(for: cell))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                }
                .buttonStyle(.plain)
            }
        }
        .id(monthIdentity)
        .transition(monthTransition)
    }

    private var monthDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let threshold: CGFloat = 42
                if value.translation.width <= -threshold {
                    shiftMonth(by: 1)
                } else if value.translation.width >= threshold {
                    shiftMonth(by: -1)
                }
            }
    }

    private func shiftMonth(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        transitionDirection = amount >= 0 ? .forward : .backward
        selectionFeedback()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
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
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.46)
    }
}

struct TaskEditorFadedOptionList: View {
    let options: [TaskEditorOptionRow]
    let selectionFeedback: () -> Void

    var body: some View {
        TaskEditorOptionList(
            options: options,
            selectionFeedback: selectionFeedback,
            usesGlassBackground: false
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct TaskEditorSingleColumnTimeWheel: View {
    @Binding var selection: Date
    let minuteInterval: Int
    var selectionCapsuleFill: Color = AppTheme.colors.pillSurface.opacity(0.96)
    var showsSelectionIcon = true

    var body: some View {
        ZStack {
            TaskEditorSingleColumnTimeWheelRepresentable(
                selection: $selection,
                minuteInterval: minuteInterval
            )
            .mask(TaskEditorSingleColumnTimeWheelFadeMask())

            TaskEditorSingleColumnTimeSelectionCapsule(
                selection: selection,
                selectionCapsuleFill: selectionCapsuleFill,
                showsIcon: showsSelectionIcon
            )
                .padding(.horizontal, 18)
                .allowsHitTesting(false)
        }
    }
}

private struct TaskEditorSingleColumnTimeWheelRepresentable: UIViewRepresentable {
    @Binding var selection: Date
    let minuteInterval: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TaskEditorSingleColumnTimeTableView {
        let tableView = TaskEditorSingleColumnTimeTableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.decelerationRate = .normal
        tableView.rowHeight = TaskEditorSingleColumnTimeWheelMetrics.rowHeight
        tableView.register(
            TaskEditorSingleColumnTimeCell.self,
            forCellReuseIdentifier: TaskEditorSingleColumnTimeCell.reuseIdentifier
        )
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.configureInitialSelection(for: tableView)
        DispatchQueue.main.async {
            tableView.reloadData()
            tableView.layoutIfNeeded()
            context.coordinator.configureInitialSelection(for: tableView)
        }
        return tableView
    }

    func updateUIView(_ uiView: TaskEditorSingleColumnTimeTableView, context: Context) {
        let roundedSelection = Self.rounded(selection, minuteInterval: minuteInterval)
        if abs(selection.timeIntervalSince(roundedSelection)) > 0.5 {
            DispatchQueue.main.async {
                selection = roundedSelection
            }
        }
        context.coordinator.parent = self
        context.coordinator.syncSelectionIfNeeded(in: uiView, targetDate: roundedSelection)
        context.coordinator.updateVisibleCells(in: uiView)
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

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate {
        var parent: TaskEditorSingleColumnTimeWheelRepresentable
        private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        private var lastCenteredRow: Int?
        private var isProgrammaticScroll = false
        private let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        init(_ parent: TaskEditorSingleColumnTimeWheelRepresentable) {
            self.parent = parent
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            slotCount * TaskEditorSingleColumnTimeWheelMetrics.loopMultiplier
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: TaskEditorSingleColumnTimeCell.reuseIdentifier,
                for: indexPath
            ) as? TaskEditorSingleColumnTimeCell ?? TaskEditorSingleColumnTimeCell(
                style: .default,
                reuseIdentifier: TaskEditorSingleColumnTimeCell.reuseIdentifier
            )
            cell.configure(text: formatter.string(from: date(for: indexPath.row)))
            return cell
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let cell = cell as? TaskEditorSingleColumnTimeCell else { return }
            applyAppearance(to: cell, in: tableView)
        }

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            let inset = max((tableView.bounds.height - TaskEditorSingleColumnTimeWheelMetrics.rowHeight) * 0.5, 0)
            if abs(tableView.contentInset.top - inset) > 0.5 || abs(tableView.contentInset.bottom - inset) > 0.5 {
                tableView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
                tableView.scrollIndicatorInsets = tableView.contentInset
                if let lastCenteredRow {
                    tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: lastCenteredRow, in: tableView)), animated: false)
                } else {
                    configureInitialSelection(for: tableView)
                }
            }
            updateVisibleCells(in: tableView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            let centeredRow = nearestRow(in: tableView)
            if centeredRow != lastCenteredRow {
                lastCenteredRow = centeredRow
                let centeredDate = date(for: centeredRow)
                if abs(parent.selection.timeIntervalSince(centeredDate)) > 0.5 {
                    parent.selection = centeredDate
                    if !isProgrammaticScroll {
                        selectionFeedbackGenerator.selectionChanged()
                    }
                }
            }
            updateVisibleCells(in: tableView)
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard let tableView = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            let targetRow = nearestRow(for: targetContentOffset.pointee.y, in: tableView)
            targetContentOffset.pointee.y = offsetY(forRow: targetRow, in: tableView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let tableView = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            snapToNearestRow(in: tableView, animated: true)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            snapToNearestRow(in: tableView, animated: true)
        }

        func configureInitialSelection(for tableView: TaskEditorSingleColumnTimeTableView) {
            let row = targetRow(for: parent.selection)
            lastCenteredRow = row
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: row, in: tableView)), animated: false)
            updateVisibleCells(in: tableView)
        }

        func syncSelectionIfNeeded(in tableView: TaskEditorSingleColumnTimeTableView, targetDate: Date) {
            guard tableView.bounds.height > 0 else { return }
            let centeredRow = nearestRow(in: tableView)
            let targetRow = targetRow(for: targetDate, preferredRow: centeredRow)
            guard targetRow != centeredRow else { return }
            isProgrammaticScroll = true
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: targetRow, in: tableView)), animated: true)
            isProgrammaticScroll = false
        }

        func updateVisibleCells(in tableView: TaskEditorSingleColumnTimeTableView) {
            for case let cell as TaskEditorSingleColumnTimeCell in tableView.visibleCells {
                applyAppearance(to: cell, in: tableView)
            }
        }

        private func applyAppearance(to cell: TaskEditorSingleColumnTimeCell, in tableView: UITableView) {
            let visibleCenterY = tableView.contentOffset.y + tableView.bounds.height * 0.5
            let distance = abs(cell.center.y - visibleCenterY)
            let normalized = min(distance / TaskEditorSingleColumnTimeWheelMetrics.rowHeight, 5)
            let isCentered = distance < (TaskEditorSingleColumnTimeWheelMetrics.rowHeight * 0.5)
            let alpha = isCentered ? 0.008 : max(0.04, 0.58 - normalized * 0.13)
            let scale = isCentered ? 1 : max(0.84, 1 - normalized * 0.04)
            cell.applyAppearance(alpha: alpha, scale: scale, isCentered: isCentered)
        }

        private var slotCount: Int {
            (24 * 60) / parent.minuteInterval
        }

        private func snapToNearestRow(in tableView: TaskEditorSingleColumnTimeTableView, animated: Bool) {
            let row = nearestRow(in: tableView)
            recenterIfNeeded(tableView, around: row)
            isProgrammaticScroll = true
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: row, in: tableView)), animated: animated)
            isProgrammaticScroll = false
            lastCenteredRow = row
            let centeredDate = date(for: row)
            if abs(parent.selection.timeIntervalSince(centeredDate)) > 0.5 {
                parent.selection = centeredDate
            }
        }

        private func nearestRow(in tableView: UITableView) -> Int {
            nearestRow(for: tableView.contentOffset.y, in: tableView)
        }

        private func nearestRow(for offsetY: CGFloat, in tableView: UITableView) -> Int {
            let raw = Int(round((offsetY + tableView.contentInset.top) / TaskEditorSingleColumnTimeWheelMetrics.rowHeight))
            return min(max(raw, 0), max(tableView.numberOfRows(inSection: 0) - 1, 0))
        }

        private func offsetY(forRow row: Int, in tableView: UITableView) -> CGFloat {
            (CGFloat(row) * TaskEditorSingleColumnTimeWheelMetrics.rowHeight) - tableView.contentInset.top
        }

        private func date(for row: Int) -> Date {
            let calendar = Calendar.current
            let slotIndex = ((row % slotCount) + slotCount) % slotCount
            let totalMinutes = slotIndex * parent.minuteInterval
            let hour = totalMinutes / 60
            let minute = totalMinutes % 60
            return calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: parent.selection
            ) ?? parent.selection
        }

        private func targetRow(for date: Date, preferredRow: Int? = nil) -> Int {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            let slotIndex = ((hour * 60) + minute) / parent.minuteInterval
            let middleCycle = TaskEditorSingleColumnTimeWheelMetrics.loopMultiplier / 2
            let base = slotIndex + middleCycle * slotCount

            guard let preferredRow else { return base }
            return [base - slotCount, base, base + slotCount]
                .min(by: { abs($0 - preferredRow) < abs($1 - preferredRow) }) ?? base
        }

        private func recenterIfNeeded(_ tableView: TaskEditorSingleColumnTimeTableView, around row: Int) {
            let cycle = row / slotCount
            let middleCycle = TaskEditorSingleColumnTimeWheelMetrics.loopMultiplier / 2
            guard abs(cycle - middleCycle) > 20 else { return }
            let centeredRow = (row % slotCount) + middleCycle * slotCount
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: centeredRow, in: tableView)), animated: false)
            lastCenteredRow = centeredRow
        }
    }
}

private struct TaskEditorSingleColumnTimeWheelFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.55), location: 0.10),
                .init(color: .black.opacity(0.86), location: 0.22),
                .init(color: .black, location: 0.32),
                .init(color: .black, location: 0.68),
                .init(color: .black.opacity(0.86), location: 0.78),
                .init(color: .black.opacity(0.55), location: 0.90),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct TaskEditorSingleColumnTimeSelectionCapsule: View {
    let selection: Date
    let selectionCapsuleFill: Color
    let showsIcon: Bool

    private var timeText: String {
        selection.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if showsIcon {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.82))
                }

                Text(timeText)
                    .contentTransition(.numericText())
                    .font(AppTheme.typography.sized(31, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
            }
            .offset(x: -3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: TaskEditorSingleColumnTimeWheelMetrics.selectionCapsuleHeight)
        .background(
            RoundedRectangle(
                cornerRadius: TaskEditorSingleColumnTimeWheelMetrics.selectionCapsuleHeight * 0.5,
                style: .continuous
            )
            .fill(selectionCapsuleFill)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: TaskEditorSingleColumnTimeWheelMetrics.selectionCapsuleHeight * 0.5,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: AppTheme.colors.shadow.opacity(0.12), radius: 16, y: 5)
        .animation(.easeInOut(duration: 0.22), value: timeText)
    }
}

private enum TaskEditorSingleColumnTimeWheelMetrics {
    static let loopMultiplier = 200
    static let rowHeight: CGFloat = 34
    static let baseFontSize: CGFloat = 19
    static let selectedFontSize: CGFloat = 24
    static let selectionCapsuleHeight: CGFloat = 62
}

final class TaskEditorSingleColumnTimeTableView: UITableView {}

final class TaskEditorSingleColumnTimeCell: UITableViewCell {
    static let reuseIdentifier = "TaskEditorSingleColumnTimeCell"

    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = false
        timeLabel.backgroundColor = .clear
        contentView.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        timeLabel.text = text
    }

    func applyAppearance(alpha: CGFloat, scale: CGFloat, isCentered: Bool) {
        timeLabel.alpha = alpha
        timeLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
        timeLabel.font = AppTheme.typography.sizedUIFont(
            isCentered ? TaskEditorSingleColumnTimeWheelMetrics.selectedFontSize : TaskEditorSingleColumnTimeWheelMetrics.baseFontSize,
            weight: isCentered ? .bold : .semibold
        )
        timeLabel.textColor = UIColor(isCentered ? AppTheme.colors.title : AppTheme.colors.body)
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
                    .fill(AppTheme.colors.pillSurface)
                    .matchedGeometryEffect(
                        id: "taskEditor.chip.\(animationID)",
                        in: namespace
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
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

struct TaskEditorChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.78), value: configuration.isPressed)
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

struct TaskEditorPrimaryActionOvershootModifier: ViewModifier {
    let trigger: Bool
    let keyboardRevealOffset: CGFloat

    private enum Motion {
        static let entryOffset: CGFloat = 62
        static let overshootOffset: CGFloat = -6
        static let entryScale: CGFloat = 0.87
        static let overshootScale: CGFloat = 1.01
        static let settleDelay: TimeInterval = 0.34
        static let entrySpring = Animation.interpolatingSpring(
            mass: 1.26,
            stiffness: 154,
            damping: 24,
            initialVelocity: 4.6
        )
        static let settleSpring = Animation.interpolatingSpring(
            mass: 1.28,
            stiffness: 94,
            damping: 26,
            initialVelocity: 0.12
        )
    }

    @State private var yOffset: CGFloat = 0
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1

    func body(content: Content) -> some View {
        content
            .offset(y: yOffset)
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
            .onAppear {
                guard trigger else { return }
                playOvershootAnimation()
            }
            .onChange(of: trigger) { _, isActive in
                guard isActive else {
                    yOffset = 0
                    scale = 1
                    opacity = 1
                    return
                }
                playOvershootAnimation()
            }
    }

    private func playOvershootAnimation() {
        yOffset = max(Motion.entryOffset, keyboardRevealOffset)
        scale = Motion.entryScale
        opacity = 0

        withAnimation(Motion.entrySpring) {
            yOffset = Motion.overshootOffset
            scale = Motion.overshootScale
            opacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.settleDelay) {
            withAnimation(Motion.settleSpring) {
                yOffset = 0
                scale = 1
                opacity = 1
            }
        }
    }
}

@MainActor
final class TaskEditorKeyboardObserver: ObservableObject {
    @Published private(set) var overlap: CGFloat = 0

    private var willChangeFrameObserver: NSObjectProtocol?
    private var willHideObserver: NSObjectProtocol?

    init() {
        let center = NotificationCenter.default

        willChangeFrameObserver = center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            Task { @MainActor [weak self] in
                self?.handleKeyboardFrame(frame)
            }
        }

        willHideObserver = center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.overlap = 0
            }
        }
    }

    deinit {
        let center = NotificationCenter.default
        if let willChangeFrameObserver {
            center.removeObserver(willChangeFrameObserver)
        }
        if let willHideObserver {
            center.removeObserver(willHideObserver)
        }
    }

    private func handleKeyboardFrame(_ frame: CGRect?) {
        guard
            let frame,
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let window = windowScene.windows.first(where: \.isKeyWindow)
        else {
            return
        }

        overlap = max(0, window.bounds.maxY - frame.minY - window.safeAreaInsets.bottom)
    }
}

enum TaskEditorMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

enum TaskEditorTimePickerMetrics {
    static let verticalInset: CGFloat = 16
    static let contentSpacing: CGFloat = 10
    static let minimumPickerHeight: CGFloat = 184
    static let pickerHeight: CGFloat = 214
}

enum TaskEditorChipAnimation {
    static let textSpring = Animation.easeInOut(duration: 0.7)
    static let layoutSpring = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let widthExpansionLead: TimeInterval = 0.12
}

struct TaskEditorDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            TaskEditorDatePickerSheet.preferredHeight + TaskEditorUnifiedMenuMetrics.topBarHeight,
            context.maxDetentValue * 0.72
        )
    }
}

struct TaskEditorTaskMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        let optionHeight = TaskEditorOptionList.preferredHeight(optionCount: 7)
        let contentHeight = max(
            TaskEditorDatePickerSheet.preferredHeight,
            TaskEditorTimePickerSheet.preferredHeight(showsQuickPresets: true, showsPrimaryButton: false),
            optionHeight
        )
        return min(
            contentHeight + TaskEditorUnifiedMenuMetrics.sheetChromeHeight,
            context.maxDetentValue * 0.88
        )
    }
}

struct TaskEditorPeriodicMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        let optionHeight = TaskEditorOptionList.preferredHeight(optionCount: 7)
        let contentHeight = max(
            TaskEditorTimePickerSheet.preferredHeight(showsQuickPresets: true, showsPrimaryButton: false),
            optionHeight
        )
        return min(
            contentHeight + TaskEditorUnifiedMenuMetrics.sheetChromeHeight,
            context.maxDetentValue * 0.88
        )
    }
}

struct TaskEditorProjectMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        let optionHeight = TaskEditorOptionList.preferredHeight(optionCount: 3)
        let contentHeight = max(
            TaskEditorDatePickerSheet.preferredHeight,
            optionHeight,
            492
        )
        return min(
            contentHeight + TaskEditorUnifiedMenuMetrics.sheetChromeHeight,
            context.maxDetentValue * 0.82
        )
    }
}

enum TaskEditorUnifiedMenuMetrics {
    static let topBarHeight: CGFloat = 64
    static let bottomSwitcherHeight: CGFloat = 58
    static let sheetChromeHeight: CGFloat = topBarHeight + bottomSwitcherHeight
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
        case .reminder, .repeatRule, .subtasks:
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

        if contentTransitionStyle == .interpolated {
            withAnimation(TaskEditorChipAnimation.textSpring) {
                displayedText = newText
            }
            withAnimation(TaskEditorChipAnimation.layoutSpring) {
                displayedWidth = targetWidth
            }
            return
        }

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
        case .repeatRule:
            return .numeric
        case .subtasks:
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
        case .date, .optionalDate, .time, .reminder, .repeatRule:
            return true
        case .subtasks:
            return false
        }
    }
}

private enum TaskEditorChipContentTransitionStyle {
    case numeric
    case interpolated
    case none
}

private enum TaskEditorChipIconEffectKind {
    case rotate
    case wiggle
    case none
}

private struct TaskEditorAnimatedChipIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let systemImage: String
    let menu: TaskEditorMenu
    let semanticValue: TaskEditorChipSemanticValue
    let font: Font

    @State private var previousSemanticValue: TaskEditorChipSemanticValue?
    @State private var effectTrigger = 0

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .applyTaskEditorChipIconEffect(
                kind: effectKind,
                trigger: effectTrigger,
                reduceMotion: reduceMotion
            )
            .onAppear {
                previousSemanticValue = semanticValue
            }
            .onChange(of: semanticValue) { oldValue, newValue in
                let baseline = previousSemanticValue ?? oldValue
                previousSemanticValue = newValue
                guard baseline != newValue else { return }
                guard effectKind != .none else { return }
                effectTrigger += 1
            }
    }

    private var effectKind: TaskEditorChipIconEffectKind {
        switch menu {
        case .time, .repeatRule:
            return .rotate
        case .reminder:
            return .wiggle
        case .date, .subtasks, .template:
            return .none
        }
    }
}

private extension View {
    @ViewBuilder
    func applyTaskEditorChipIconEffect(
        kind: TaskEditorChipIconEffectKind,
        trigger: Int,
        reduceMotion: Bool
    ) -> some View {
        if reduceMotion {
            self
        } else {
            switch kind {
            case .rotate:
                if #available(iOS 18.0, *) {
                    self.symbolEffect(.rotate.clockwise, options: .speed(1.12), value: trigger)
                } else {
                    self.symbolEffect(.bounce, options: .speed(1.08), value: trigger)
                }
            case .wiggle:
                if #available(iOS 18.0, *) {
                    self.symbolEffect(.wiggle.clockwise, options: .speed(1.12), value: trigger)
                } else {
                    self.symbolEffect(.bounce, options: .speed(1.1), value: trigger)
                }
            case .none:
                self
            }
        }
    }
}

private struct TaskEditorDatePickerMonthGridMetrics {
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let dayFontSize: CGFloat
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
