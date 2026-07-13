import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RoutinesEditorSheet: View {
    let viewModel: RoutinesViewModel

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var cycle: PeriodicCycle
    @State private var reminderRules: [PeriodicReminderRule] = []

    @State private var primaryActionFeedbackNonce = 0
    @State private var isPrimaryActionAnimating = false
    @State private var activeInlineAttributeEditor: InlineAttributeEditor?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    init(viewModel: RoutinesViewModel, initialCycle: PeriodicCycle = .daily) {
        self.viewModel = viewModel
        _cycle = State(initialValue: initialCycle)
    }

    enum Field: Hashable {
        case title
        case notes
    }

    private var hasMeaningfulContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                        TextField("事务名称", text: $title, axis: .vertical)
                            .font(AppTheme.typography.sized(28, weight: .bold))
                            .foregroundStyle(AppTheme.colors.title)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .title)

                        TextField("添加备注...", text: $notes, axis: .vertical)
                            .font(AppTheme.typography.sized(16, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.78))
                            .lineLimit(1...8)
                            .textInputAutocapitalization(.sentences)
                            .focused($focusedField, equals: .notes)
                    }
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.top, AppTheme.spacing.md)
                    .padding(.bottom, 160) // scroll-content bottom offset, outside token scale
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.colors.surface)
            .overlay(alignment: .bottom) {
                bottomActionArea(bottomInset: max(proxy.safeAreaInsets.bottom, AppTheme.spacing.xs))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.colors.surface)
        .alert(
            "无法使用原生闹钟",
            isPresented: Binding(
                get: { viewModel.showsAlarmAuthorizationDeniedAlert },
                set: { viewModel.showsAlarmAuthorizationDeniedAlert = $0 }
            )
        ) {
            Button("取消", role: .cancel) {}
            Button("打开设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text("请在系统设置中允许 Together 使用闹钟；当前提醒方式保持不变。")
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
    }

    // MARK: - Bottom Action Area

    private func bottomActionArea(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: hasMeaningfulContent ? AppTheme.spacing.md : 0) {
                attributeToolbar

                if hasMeaningfulContent {
                    primaryActionButton
                }
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.md)
            .padding(.bottom, AppTheme.spacing.md)
            .background(
                LinearGradient(
                    colors: [.clear, AppTheme.colors.surface.opacity(0.97)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(.bottom, bottomInset)
        .animation(.interpolatingSpring(mass: 1.08, stiffness: 168, damping: 23, initialVelocity: 0.1), value: hasMeaningfulContent)
    }

    // MARK: - Inline Attributes

    private var attributeToolbar: some View {
        AdaptiveTaskAttributeToolbarLayout() {
            cycleMenu.frame(maxWidth: .infinity)
            targetDayMenu.frame(maxWidth: .infinity)
            targetTimeControl.frame(maxWidth: .infinity)
            reminderMenu.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $activeInlineAttributeEditor) { editor in
            inlineAttributeEditor(editor)
        }
    }

    private var cycleMenu: some View {
        Menu {
            ForEach(PeriodicCycle.allCases, id: \.self) { value in
                Button {
                    cycle = value
                    if let rule = reminderRules.first {
                        setRule(RoutinesViewModel.normalizedRule(rule, for: value))
                    }
                } label: {
                    if cycle == value {
                        Label(value.title, systemImage: "checkmark")
                    } else {
                        Text(value.title)
                    }
                }
            }
        } label: {
            attributeLabel(icon: "arrow.triangle.2.circlepath", title: cycle.title, configured: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var targetDayMenu: some View {
        if cycle == .daily {
            attributeLabel(icon: "calendar", title: "每天", configured: true)
        } else {
            Menu {
                targetDayOptions
                if currentRule?.hasTargetDay == true {
                    Divider()
                    Button("清除目标日", role: .destructive) { mutateRule { $0.timing = nil } }
                }
            } label: {
                attributeLabel(icon: "calendar", title: targetDayTitle, configured: currentRule?.hasTargetDay == true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var targetTimeControl: some View {
        TaskAttributeButton(
            icon: "clock",
            title: currentRule?.hasTargetTime == true ? TaskAttributeValueText.time(targetTimeDate) : "时间",
            isConfigured: currentRule?.hasTargetTime == true
        ) {
            focusedField = nil
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.01)) {
                activeInlineAttributeEditor = activeInlineAttributeEditor == .time ? nil : .time
            }
        }
    }

    private var reminderMenu: some View {
        Menu {
            Button {
                mutateRule { $0.reminderLeadMinutes = nil; $0.reminderDelivery = nil }
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
                    mutateRule { $0.reminderDelivery = .notification }
                } label: {
                    Label(
                        "普通通知",
                        systemImage: currentRule?.reminderDelivery == .notification ? "checkmark" : "bell"
                    )
                }
                if #available(iOS 26.0, *) {
                    Button {
                        Task {
                            let accepted = await viewModel.canUseAlarmDelivery()
                            guard accepted else { return }
                            mutateRule { $0.reminderDelivery = .alarm }
                        }
                    } label: {
                        Label(
                            "原生闹钟",
                            systemImage: currentRule?.reminderDelivery == .alarm ? "checkmark" : "alarm"
                        )
                    }
                }
            }
        } label: {
            attributeLabel(
                icon: currentRule?.reminderDelivery == .alarm ? "alarm" : "bell",
                title: currentRule?.hasReminder == true ? "提醒" : "提醒",
                configured: currentRule?.hasReminder == true
            )
        }
        .buttonStyle(.plain)
        .disabled(currentRule?.hasCompleteTarget(for: cycle) != true)
    }

    private func reminderOption(_ title: String, minutes: Int) -> some View {
        Button {
            mutateRule {
                $0.reminderLeadMinutes = minutes
                if $0.reminderDelivery == nil { $0.reminderDelivery = .notification }
            }
        } label: {
            if currentRule?.reminderLeadMinutes == minutes {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func inlineAttributeEditor(_ editor: InlineAttributeEditor) -> some View {
        InlineDateTimePickerPanel(
            editor: editor,
            title: "选择目标时间",
            initialSelection: currentRule?.hasTargetTime == true ? targetTimeDate : nil,
            fallbackSelection: .now,
            supportsClearing: currentRule?.hasTargetTime == true,
            onCommit: { value in
                if let value {
                    updateTargetTime(value)
                } else {
                    mutateRule {
                        $0.hour = nil
                        $0.minute = nil
                        $0.reminderLeadMinutes = nil
                        $0.reminderDelivery = nil
                    }
                }
            }
        )
    }

    private func attributeLabel(icon: String, title: String, configured: Bool) -> some View {
        TaskAttributeLabel(
            icon: icon,
            title: title,
            isConfigured: configured
        )
    }

    @ViewBuilder
    private var targetDayOptions: some View {
        switch cycle {
        case .daily:
            EmptyView()
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

    private var currentRule: PeriodicReminderRule? { reminderRules.first }

    private var targetDayTitle: String {
        guard let rule = currentRule else { return "目标日" }
        let text = RoutineTargetText.text(
            for: PeriodicReminderRule(timing: rule.timing),
            cycle: cycle
        )
        return text.isEmpty ? "目标日" : text
    }

    private var targetTimeDate: Date {
        Calendar.current.date(from: DateComponents(hour: currentRule?.hour, minute: currentRule?.minute)) ?? .now
    }

    private func updateTargetTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        mutateRule { $0.hour = components.hour; $0.minute = components.minute }
    }

    private func mutateRule(_ mutation: (inout PeriodicReminderRule) -> Void) {
        var rule = currentRule ?? PeriodicReminderRule()
        mutation(&rule)
        setRule(rule)
    }

    private func setRule(_ rule: PeriodicReminderRule) {
        reminderRules = rule.isEmpty ? [] : [rule]
    }

    // MARK: - Primary Action Button

    private var primaryActionButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            triggerPrimaryActionAnimation()
            save()
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .symbolEffect(.bounce, value: primaryActionFeedbackNonce)
                Text("创建")
                    .font(AppTheme.typography.sized(15, weight: .bold))
            }
            .foregroundStyle(AppTheme.colors.title)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .padding(.horizontal, AppTheme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.xxl, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.radius.xxl, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPrimaryActionAnimating ? 0.95 : 1)
        .brightness(isPrimaryActionAnimating ? -0.015 : 0)
        .shadow(color: AppTheme.colors.shadow, radius: 14, y: 7)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isPrimaryActionAnimating)
        .padding(.horizontal, AppTheme.spacing.sm)
        .transition(.offset(y: 18).combined(with: .opacity))
    }

    private func triggerPrimaryActionAnimation() {
        primaryActionFeedbackNonce += 1
        isPrimaryActionAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isPrimaryActionAnimating = false
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let draft = PeriodicTaskDraft(
            title: trimmedTitle,
            notes: notes.isEmpty ? nil : notes,
            cycle: cycle,
            reminderRules: reminderRules.filter { $0.isEmpty == false }
        )

        Task {
            await viewModel.createTask(draft: draft)
            dismiss()
            viewModel.dismissEditor()
        }
    }
}

// MARK: - Routines Editor Menu Sheet

private struct RoutinesEditorMenuSheet: View {
    @Binding var activeMenu: TaskEditorMenu
    @Binding var cycle: PeriodicCycle
    @Binding var reminderRules: [PeriodicReminderRule]
    let onDismiss: () -> Void

    var body: some View {
        TaskEditorUnifiedMenuSheet(
            context: .periodic,
            activeMenu: $activeMenu,
            selectionFeedback: HomeInteractionFeedback.selection,
            switcherPlacement: .bottom,
            onClose: onDismiss,
            onSave: onDismiss
        ) { menu in
            menuContent(for: menu)
        }
    }

    @ViewBuilder
    private func menuContent(for menu: TaskEditorMenu) -> some View {
        switch menu {
        case .periodicCycle:
            periodicCyclePanel
        case .periodicReminder:
            periodicReminderPanel
        default:
            EmptyView()
        }
    }

    private var periodicCyclePanel: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing.sm) {
                ForEach(PeriodicCycle.allCases, id: \.self) { c in
                    Button {
                        HomeInteractionFeedback.selection()
                        cycle = c
                        if let first = reminderRules.first {
                            let normalized = RoutinesViewModel.normalizedRule(first, for: c)
                            reminderRules = normalized.isEmpty ? [] : [normalized]
                        }
                    } label: {
                        HStack {
                            Text(c.title)
                                .font(AppTheme.typography.sized(17, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            Spacer(minLength: 0)
                            if cycle == c {
                                Image(systemName: "checkmark")
                                    .font(AppTheme.typography.sized(14, weight: .bold))
                                    .foregroundStyle(AppTheme.colors.coral)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: TaskEditorMenuOptionMetrics.height)
                        .padding(.horizontal, AppTheme.spacing.md)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var periodicReminderPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(reminderRules.indices, id: \.self) { index in
                    RoutinesReminderRulePicker(
                        rule: $reminderRules[index],
                        cycle: cycle
                    )
                    .padding(.horizontal, AppTheme.spacing.lg)

                    if index < reminderRules.count - 1 {
                        Divider()
                            .padding(.horizontal, AppTheme.spacing.lg)
                            .padding(.vertical, AppTheme.spacing.xs)
                    }
                }
            }
            .padding(.top, AppTheme.spacing.xs)
            .padding(.bottom, AppTheme.spacing.lg)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if reminderRules.isEmpty {
                reminderRules = [PeriodicReminderRule()]
            }
        }
    }
}
