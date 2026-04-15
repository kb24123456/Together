import SwiftUI

struct RoutinesDetailSheet: View {
    @Bindable var viewModel: RoutinesViewModel

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var cycle: PeriodicCycle = .monthly
    @State private var reminderEnabled = false
    @State private var reminderRules: [PeriodicReminderRule] = []

    @State private var activeMenu: TaskEditorMenu?
    @State private var pendingAction: DetailEntryAction?
    @State private var isAwaitingDeleteConfirmation = false
    @State private var templateSaveState: RoutinesTemplateSaveState = .idle
    @State private var saveFeedbackNonce = 0
    @State private var isSaveButtonAnimating = false

    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss
    @Namespace private var chipRowNamespace
    @Namespace private var categorySwitcherNamespace

    enum Field: Hashable {
        case title
        case notes
    }

    private enum DetailEntryAction {
        case none
        case focus(Field)
        case menu(TaskEditorMenu)
    }

    private var task: PeriodicTask? { viewModel.detailTask }

    private var isExpandedEditor: Bool {
        viewModel.detailDetent == .large
    }

    // MARK: - Body

    var body: some View {
        Group {
            if task != nil {
                GeometryReader { proxy in
                    Group {
                        if isExpandedEditor {
                            expandedEditorLayout(proxy: proxy)
                        } else {
                            compactDetailLayout(proxy: proxy)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                Color.clear
            }
        }
        .background(isExpandedEditor ? AppTheme.colors.surface : .clear)
        .overlay {
            if activeMenu != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissActiveMenu() }
            }
        }
        .sheet(isPresented: isMenuSheetPresented, onDismiss: {
            // no-op
        }) {
            if let menuBinding = activeMenuBinding {
                RoutinesDetailMenuSheet(
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
        .presentationDetents([.height(316), .large], selection: $viewModel.detailDetent)
        .presentationDragIndicator(.hidden)
        .presentationBackground(AppTheme.colors.surface)
        .onChange(of: focusedField) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.expandDetailToEdit()
            }
        }
        .onChange(of: viewModel.detailDetent) { _, newValue in
            guard newValue == .large else { return }
            performPendingActionIfNeeded()
        }
        .onAppear {
            if let task {
                title = task.title
                notes = task.notes ?? ""
                cycle = task.cycle
                reminderRules = task.reminderRules
                reminderEnabled = !task.reminderRules.isEmpty
            }
        }
        .onDisappear {
            // Sync reminder enabled state from rules
        }
    }

    // MARK: - Compact Detail Layout

    private func compactDetailLayout(proxy: GeometryProxy) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if isAwaitingDeleteConfirmation || templateSaveState != .idle {
                        cancelInlineActions()
                    } else {
                        viewModel.dismissDetail()
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                compactHeaderSection
                compactMetaSection
                    .padding(.top, 38)
                compactChipSection
                    .padding(.top, 14)
                compactActionButtons
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compactHeaderSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.title))
            } label: {
                Text(task?.title ?? "")
                    .font(adaptiveCompactTitleFont)
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(.plain)

            Button {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.notes))
            } label: {
                Text(compactNotesText)
                    .font(AppTheme.typography.sized(18, weight: .medium))
                    .foregroundStyle(compactNotesColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var compactMetaSection: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(currentStateText)
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(statusTextColor)
        }
    }

    private var compactChipSection: some View {
        chipRow { menu in
            HomeInteractionFeedback.selection()
            expandToLarge(for: .menu(menu))
        }
    }

    private var compactActionButtons: some View {
        HStack(spacing: 10) {
            compactTemplateButton
            compactEditButton
            compactDeleteButton
        }
    }

    private var compactTemplateButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            handleTemplateSaveTap()
        } label: {
            ZStack {
                if case .saved = templateSaveState {
                    compactActionContent(
                        title: "成功",
                        systemImage: "checkmark.circle.fill",
                        tint: AppTheme.colors.body
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else {
                    compactActionContent(
                        title: "存模板",
                        systemImage: "bookmark",
                        tint: AppTheme.colors.body
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.72), lineWidth: 1)
            }
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: templateSaveState)
        }
        .buttonStyle(.plain)
    }

    private func handleTemplateSaveTap() {
        guard case .idle = templateSaveState else { return }
        guard let task else { return }
        Task {
            guard let result = await viewModel.saveAsTemplate(task: task) else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    templateSaveState = .saved(templateID: result.templateID, isNewlyCreated: result.isNewlyCreated)
                }
            }
        }
    }

    private var compactEditButton: some View {
        compactActionButton(
            title: "编辑",
            systemImage: "pencil",
            tint: AppTheme.colors.body
        ) {
            HomeInteractionFeedback.selection()
            expandToLarge(for: .focus(.title))
        }
        .disabled(!canEditDetailTask)
        .opacity(canEditDetailTask ? 1 : 0.4)
    }

    private var canDeleteDetailTask: Bool {
        guard let task else { return true }
        return viewModel.canDeletePeriodicTask(task)
    }

    private var canEditDetailTask: Bool {
        guard let task else { return true }
        return viewModel.canEditPeriodicTask(task)
    }

    private var compactDeleteButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            if isAwaitingDeleteConfirmation {
                deleteAndDismiss()
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isAwaitingDeleteConfirmation = true
                }
            }
        } label: {
            compactActionContent(
                title: isAwaitingDeleteConfirmation ? "确认" : "移除",
                systemImage: isAwaitingDeleteConfirmation ? "checkmark" : "trash",
                tint: AppTheme.colors.coral
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.68), lineWidth: 1)
            }
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isAwaitingDeleteConfirmation)
        }
        .buttonStyle(.plain)
        .disabled(!canDeleteDetailTask)
        .opacity(canDeleteDetailTask ? 1 : 0.4)
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            compactActionContent(title: title, systemImage: systemImage, tint: tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 84)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.colors.pillSurface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppTheme.colors.pillOutline.opacity(0.72), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func compactActionContent(
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(22, weight: .semibold))
                .frame(height: 24, alignment: .center)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(AppTheme.typography.sized(17, weight: .semibold))
                .lineLimit(1)
                .contentTransition(.interpolate)
                .frame(height: 24, alignment: .center)
        }
        .foregroundStyle(tint)
    }

    // MARK: - Expanded Editor Layout

    private func expandedEditorLayout(proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            expandedCategorySwitcher
                .padding(.top, 18)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("事务名称", text: $title, axis: .vertical)
                        .font(AppTheme.typography.sized(28, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)
                        .focused($focusedField, equals: .title)

                    TextField("添加备注...", text: $notes, axis: .vertical)
                        .font(AppTheme.typography.sized(16, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.78))
                        .focused($focusedField, equals: .notes)
                }
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 160)
                .disabled(!canEditDetailTask)
                .opacity(canEditDetailTask ? 1 : 0.7)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            expandedBottomActionArea(bottomInset: max(proxy.safeAreaInsets.bottom, 8))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var expandedCategorySwitcher: some View {
        HStack(spacing: 10) {
            ForEach(["模板", "任务", "周期", "项目"], id: \.self) { title in
                let isActive = title == "周期"

                Button {
                    if isActive {
                        HomeInteractionFeedback.selection()
                        focusedField = .title
                    }
                } label: {
                    Text(title)
                        .font(AppTheme.typography.sized(18, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? AppTheme.colors.title : AppTheme.colors.textTertiary)
                        .scaleEffect(isActive ? 1 : 0.96)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 9)
                        .background(
                            ZStack {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.colors.surfaceElevated)
                                        .matchedGeometryEffect(
                                            id: "routinesDetail.categorySwitcher.selection",
                                            in: categorySwitcherNamespace
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isActive)
            }
        }
        .padding(.bottom, 10)
    }

    private func expandedBottomActionArea(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text(currentStateText)
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(statusTextColor)

                chipRow { menu in
                    guard activeMenu == nil else { return }
                    HomeInteractionFeedback.selection()
                    openMenu(menu)
                }

                expandedSaveButton
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
        .animation(.interpolatingSpring(mass: 1.08, stiffness: 168, damping: 23, initialVelocity: 0.1), value: isExpandedEditor)
    }

    private var expandedSaveButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            triggerSaveButtonAnimation()
            if hasUnsavedChanges {
                save()
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    viewModel.detailDetent = .height(316)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                    .symbolEffect(.bounce, value: saveFeedbackNonce)
                Text("保存")
                    .font(AppTheme.typography.sized(15, weight: .bold))
            }
            .foregroundStyle(AppTheme.colors.title)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
        .padding(.horizontal, 10)
        .scaleEffect(isSaveButtonAnimating ? 0.95 : 1)
        .brightness(isSaveButtonAnimating ? -0.015 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isSaveButtonAnimating)
        .transition(.offset(y: 18).combined(with: .opacity))
    }

    // MARK: - Shared Chip Row

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
        // Sync reminderEnabled from rules
        reminderEnabled = !reminderRules.isEmpty
    }

    // MARK: - Navigation Helpers

    private func expandToLarge(for action: DetailEntryAction) {
        cancelInlineActions()
        pendingAction = action

        if isExpandedEditor {
            performPendingActionIfNeeded()
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            viewModel.expandDetailToEdit()
        }
    }

    private func performPendingActionIfNeeded() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .none:
            break
        case let .focus(field):
            DispatchQueue.main.async {
                focusedField = field
            }
        case let .menu(menu):
            openMenu(menu)
        }
    }

    private func cancelInlineActions() {
        if isAwaitingDeleteConfirmation {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                isAwaitingDeleteConfirmation = false
            }
        }

        guard case let .saved(templateID, isNewlyCreated) = templateSaveState else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            templateSaveState = .idle
        }
        guard isNewlyCreated else { return }
        Task {
            await viewModel.deleteTemplate(templateID: templateID)
        }
    }

    private func triggerSaveButtonAnimation() {
        saveFeedbackNonce += 1
        isSaveButtonAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isSaveButtonAnimating = false
        }
    }

    // MARK: - Data Helpers

    private var hasUnsavedChanges: Bool {
        guard let task else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalNotes = (task.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle != task.title
            || trimmedNotes != originalNotes
            || cycle != task.cycle
            || reminderRules != task.reminderRules
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

    private var adaptiveCompactTitleFont: Font {
        let titleCount = (task?.title ?? "").count
        switch titleCount {
        case 0...16: return AppTheme.typography.sized(32, weight: .bold)
        case 17...28: return AppTheme.typography.sized(29, weight: .bold)
        case 29...42: return AppTheme.typography.sized(26, weight: .bold)
        default: return AppTheme.typography.sized(23, weight: .bold)
        }
    }

    private var compactNotesText: String {
        let text = (task?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "添加备注..." : text
    }

    private var compactNotesColor: Color {
        let text = (task?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? AppTheme.colors.textTertiary.opacity(0.74) : AppTheme.colors.body.opacity(0.78)
    }

    private var currentStateText: String {
        guard let task else { return "" }
        return "\(task.cycle.currentPeriodPrefix) · \(statusLabelText)"
    }

    private var statusTextColor: Color {
        guard let task else { return AppTheme.colors.body }
        switch viewModel.urgencyState(task) {
        case .pastReminder: return AppTheme.colors.coral
        case .completed: return AppTheme.colors.success
        default: return AppTheme.colors.body.opacity(0.84)
        }
    }

    private var statusLabelText: String {
        guard let task else { return "" }
        switch viewModel.urgencyState(task) {
        case .completed: return "已完成"
        case .pastReminder: return "已逾期"
        case .approaching: return "临近截止"
        case .normal: return "待完成"
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let task else { return }

        let draft = PeriodicTaskDraft(
            title: trimmedTitle,
            notes: notes.isEmpty ? nil : notes,
            cycle: cycle,
            reminderRules: reminderRules
        )

        Task {
            await viewModel.updateTask(taskID: task.id, draft: draft)
            // Refresh detail task
            if let updated = viewModel.tasks.first(where: { $0.id == task.id }) {
                viewModel.detailTask = updated
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                viewModel.detailDetent = .height(316)
            }
        }
    }

    private func deleteAndDismiss() {
        guard let task else { return }
        Task {
            await viewModel.deleteTask(taskID: task.id)
            dismiss()
            viewModel.dismissDetail()
        }
    }
}

enum RoutinesTemplateSaveState: Equatable {
    case idle
    case saved(templateID: UUID, isNewlyCreated: Bool)
}

struct RoutinesTemplateSaveResult: Sendable, Equatable {
    let templateID: UUID
    let isNewlyCreated: Bool
}

// MARK: - Routines Detail Menu Sheet

private struct RoutinesDetailMenuSheet: View {
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
            VStack(spacing: 10) {
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
                    .padding(.horizontal, 20)

                    if index < reminderRules.count - 1 {
                        Divider()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
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
