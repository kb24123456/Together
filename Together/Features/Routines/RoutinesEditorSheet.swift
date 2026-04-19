import SwiftUI

struct RoutinesEditorSheet: View {
    let viewModel: RoutinesViewModel

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var cycle: PeriodicCycle = .monthly
    @State private var reminderRules: [PeriodicReminderRule] = []

    @State private var activeMenu: TaskEditorMenu?
    @State private var primaryActionFeedbackNonce = 0
    @State private var isPrimaryActionAnimating = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @Namespace private var chipRowNamespace

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
                            .focused($focusedField, equals: .title)

                        TextField("添加备注...", text: $notes, axis: .vertical)
                            .font(AppTheme.typography.sized(16, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.78))
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
            .overlay {
                if activeMenu != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissActiveMenu() }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: isMenuSheetPresented) {
            if let menuBinding = activeMenuBinding {
                RoutinesEditorMenuSheet(
                    activeMenu: menuBinding,
                    cycle: $cycle,
                    reminderRules: $reminderRules,
                    onDismiss: dismissActiveMenu
                )
                .presentationDetents(TaskEditorMenuContext.periodic.detents)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
                .modifier(TaskEditorMenuPresentationSizingModifier())
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.colors.surface)
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
                chipRow { menu in
                    HomeInteractionFeedback.selection()
                    openMenu(menu)
                }

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

    // MARK: - Chip Row

    private func chipRow(action: @escaping (TaskEditorMenu) -> Void) -> some View {
        TaskEditorChipRow(
            chips: chips,
            namespace: chipRowNamespace,
            trailingInset: 0,
            onChipTap: action,
            onClearTap: { _ in }
        )
    }

    private var chips: [TaskEditorRenderedChip] {
        let snapshots: [TaskEditorChipSnapshot] = [
            TaskEditorChipSnapshot(
                id: TaskEditorMenu.periodicCycle.rawValue,
                title: cycle.title,
                systemImage: "arrow.clockwise",
                menu: .periodicCycle,
                semanticValue: .periodicCycle(cycle)
            ),
            TaskEditorChipSnapshot(
                id: TaskEditorMenu.periodicReminder.rawValue,
                title: reminderChipTitle,
                systemImage: "bell",
                menu: .periodicReminder,
                semanticValue: .periodicReminder(!reminderRules.isEmpty)
            )
        ]
        return snapshots.map { snapshot in
            TaskEditorRenderedChip(
                id: snapshot.id,
                title: snapshot.title,
                systemImage: snapshot.systemImage,
                menu: snapshot.menu,
                showsTrailingClear: false,
                transitionDirection: .up,
                semanticValue: snapshot.semanticValue
            )
        }
    }

    private var reminderChipTitle: String {
        guard let rule = reminderRules.first else { return "提醒" }
        let timeString = String(format: "%02d:%02d", rule.hour, rule.minute)
        switch rule.timing {
        case .dayOfPeriod(let day):
            return "第\(day)天 \(timeString)"
        case .businessDayOfPeriod(let day):
            return "第\(day)工作日"
        case .daysBeforeEnd(let days):
            return "前\(days)天 \(timeString)"
        }
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

    // MARK: - Menu Management

    private var isMenuSheetPresented: Binding<Bool> {
        Binding(
            get: { activeMenu != nil },
            set: { if !$0 { dismissActiveMenu() } }
        )
    }

    private var activeMenuBinding: Binding<TaskEditorMenu>? {
        guard let activeMenu else { return nil }
        return Binding(
            get: { self.activeMenu ?? activeMenu },
            set: { self.activeMenu = $0 }
        )
    }

    private func openMenu(_ menu: TaskEditorMenu) {
        focusedField = nil
        activeMenu = menu
    }

    private func dismissActiveMenu() {
        activeMenu = nil
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let draft = PeriodicTaskDraft(
            title: trimmedTitle,
            notes: notes.isEmpty ? nil : notes,
            cycle: cycle,
            reminderRules: reminderRules
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
                reminderRules = [defaultRule(for: cycle)]
            }
        }
    }

    private func defaultRule(for cycle: PeriodicCycle) -> PeriodicReminderRule {
        switch cycle {
        case .weekly: PeriodicReminderRule(timing: .dayOfPeriod(3))
        case .monthly: PeriodicReminderRule(timing: .dayOfPeriod(20))
        case .quarterly: PeriodicReminderRule(timing: .daysBeforeEnd(14))
        case .yearly: PeriodicReminderRule(timing: .daysBeforeEnd(30))
        }
    }
}
