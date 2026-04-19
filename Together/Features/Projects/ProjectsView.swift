import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ProjectsPresentationStyle {
    case screen
    case layer
}

struct ProjectsView: View {
    @Bindable var viewModel: ProjectsViewModel
    let style: ProjectsPresentationStyle

    init(
        viewModel: ProjectsViewModel,
        style: ProjectsPresentationStyle = .screen
    ) {
        self.viewModel = viewModel
        self.style = style
    }

    var body: some View {
        ProjectsListContent(
            viewModel: viewModel,
            style: style,
            showsHeader: true,
            isPresented: true,
            contentTopPadding: style == .layer ? 150 : AppTheme.spacing.xl, // layer chrome offset, outside token scale
            contentBottomPadding: style == .layer ? 240 : AppTheme.spacing.xl // layer chrome offset, outside token scale
        )
        .background(backgroundView)
        .navigationTitle(style == .screen ? "项目" : "")
        .toolbar(style == .screen ? .visible : .hidden, for: .navigationBar)
    }

    private var backgroundView: some View {
        Group {
            if style == .layer {
                AppTheme.colors.projectLayerBackground.ignoresSafeArea()
            } else {
                GradientGridBackground()
            }
        }
    }

}

struct ProjectsListContent: View {
    @Environment(AppContext.self) private var appContext
    @Bindable var viewModel: ProjectsViewModel
    let style: ProjectsPresentationStyle
    let showsHeader: Bool
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat
    @State private var expansionState = ProjectExpansionPresentationState()
    @State private var editingProjectID: UUID?
    @State private var titleDraft = ""
    @State private var datePickerProjectID: UUID?
    @State private var stagedTargetDate = Date()
    @State private var showsArchivedProjects = false
    @State private var hasAppliedEntryExpansion = false
    @State private var dockHideTask: Task<Void, Never>?
    private let horizontalInset = AppTheme.spacing.xl
    private let expandAnimation = Animation.snappy(duration: 0.42, extraBounce: 0.06)
    private let collapseAnimation = Animation.snappy(duration: 0.28, extraBounce: 0)
    private let projectHeaderProtectionHeight: CGFloat = 126

    var body: some View {
        rootContent
            .sensoryFeedback(.selection, trigger: expansionState.animationBatch)
            .task {
                guard viewModel.loadState == .idle else { return }
            await viewModel.load()
        }
        .onAppear {
            applyEntryExpansionIfNeeded()
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                applyEntryExpansionIfNeeded()
                Task { await viewModel.load() }
            } else {
                hasAppliedEntryExpansion = false
                editingProjectID = nil
                titleDraft = ""
            }
        }
        .onChange(of: visibleProjectIDs) { _, _ in
            if isPresented, hasAppliedEntryExpansion == false {
                applyEntryExpansionIfNeeded()
            } else {
                expansionState.syncVisibleProjectIDs(visibleProjectIDs)
            }
        }
        .onChange(of: showsArchivedProjects) { _, isShowing in
            if isShowing {
                expansionState.syncVisibleProjectIDs(visibleProjectIDs)
            }
        }
        .modifier(
            ProjectDeadlineSheetModifier(
                project: datePickerBinding,
                stagedTargetDate: $stagedTargetDate,
                onDismiss: { project in
                    datePickerProjectID = nil
                    Task {
                        await commitTargetDate(for: project.id, value: stagedTargetDate)
                    }
                }
            )
        )
    }

    private var rootContent: some View {
        GeometryReader { proxy in
            contentStack(proxy: proxy)
        }
    }

    private func contentStack(proxy: GeometryProxy) -> some View {
        ZStack {
            scrollContent

            if style == .layer {
                projectChromeOverlay(proxy: proxy)
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            scrollSections
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
        }
        .applyScrollEdgeProtection()
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newOffset in
            handleScrollOffsetChange(to: newOffset)
        }
    }

    private func handleScrollOffsetChange(to newOffset: CGFloat) {
        let homeViewModel = appContext.homeViewModel
        let shouldHide = newOffset > 30

        dockHideTask?.cancel()

        if shouldHide {
            if !homeViewModel.isDockHidden {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    homeViewModel.isDockHidden = true
                }
            }
            dockHideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    homeViewModel.isDockHidden = false
                }
            }
        } else {
            if homeViewModel.isDockHidden {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    homeViewModel.isDockHidden = false
                }
            }
        }
    }

    private var scrollSections: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
            if showsHeader {
                headerSection
            }

            activeProjectsSection

            if viewModel.archivedProjects.isEmpty == false {
                archivedProjectsEntry(sectionIndex: 1)
            }

            if showsArchivedProjects, viewModel.archivedProjects.isEmpty == false {
                archivedProjectsSection
            }
        }
    }

    private var activeProjectsSection: some View {
        projectSection(
            projects: viewModel.activeProjects,
            sectionIndex: 0,
            topInset: projectModeTopProtectionInset
        )
    }

    private var archivedProjectsSection: some View {
        projectSection(
            projects: viewModel.archivedProjects,
            sectionIndex: 2,
            topInset: 0
        )
    }

    @ViewBuilder
    private var headerSection: some View {
        EmptyView()
    }

    private func projectSection(
        projects: [Project],
        sectionIndex: Int,
        topInset: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if projects.isEmpty {
                ProjectCascadeItem(isVisible: isPresented, index: sectionIndex * 3 + 1) {
                    emptyState
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        let isExpanded = expansionState.expandedProjectIDs.contains(project.id)

                        ProjectCascadeItem(isVisible: isPresented, index: sectionIndex * 6 + index + 1) {
                            ProjectListRow(
                                project: project,
                                style: style,
                                isExpanded: isExpanded,
                                isEditingTitle: editingProjectID == project.id,
                                animationBatch: expansionState.animationBatch,
                                titleDraft: titleBinding(for: project.id),
                                onToggleExpanded: {
                                    toggleExpanded(project.id)
                                },
                                onToggleCompletion: {
                                    if project.status != .completed, isExpanded {
                                        withAnimation(collapseAnimation) {
                                            expansionState.toggle(project.id)
                                        }
                                    }
                                    Task {
                                        await viewModel.toggleProjectCompletion(projectID: project.id)
                                    }
                                },
                                onToggleSubtask: { subtaskID in
                                    Task {
                                        await viewModel.toggleSubtask(projectID: project.id, subtaskID: subtaskID)
                                    }
                                },
                                onUpdateSubtask: { subtaskID, title in
                                    Task {
                                        await viewModel.updateSubtask(projectID: project.id, subtaskID: subtaskID, title: title)
                                    }
                                },
                                onAddSubtask: { title in
                                    Task {
                                        await viewModel.addSubtask(projectID: project.id, title: title)
                                    }
                                },
                                onBeginTitleEditing: {
                                    guard viewModel.canEditProject(project) else { return }
                                    HomeInteractionFeedback.selection()
                                    editingProjectID = project.id
                                    titleDraft = project.name
                                },
                                onCommitTitle: { title in
                                    editingProjectID = nil
                                    Task {
                                        await commitTitle(for: project.id, value: title)
                                    }
                                },
                                onOpenDeadlineEditor: {
                                    HomeInteractionFeedback.selection()
                                    editingProjectID = nil
                                    stagedTargetDate = project.targetDate ?? .now
                                    datePickerProjectID = project.id
                                },
                                onSubtitleTapped: {
                                    toggleExpanded(project.id)
                                },
                                onRequestAddSubtask: {
                                    toggleExpanded(project.id)
                                }
                            )
                        }
                        .projectContextMenu(
                            project: project,
                            canDelete: viewModel.canDeleteProject(project),
                            onDelete: {
                                HomeInteractionFeedback.selection()
                                editingProjectID = nil
                                titleDraft = ""
                                Task {
                                    await viewModel.deleteProject(projectID: project.id)
                                }
                            }
                        )
                        .padding(.top, index == 0 ? topInset : 0)

                    }
                }
            }
        }
    }

    private func archivedProjectsEntry(sectionIndex: Int) -> some View {
        ProjectCascadeItem(isVisible: isPresented, index: sectionIndex * 6 + 1) {
            Button {
                HomeInteractionFeedback.selection()
                withAnimation(showsArchivedProjects ? collapseAnimation : expandAnimation) {
                    showsArchivedProjects.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.spacing.xs) {
                    Text(showsArchivedProjects ? "收起已完成项目" : "查看已完成项目")
                        .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                        .foregroundStyle(sectionSubtitleColor)

                    Image(systemName: showsArchivedProjects ? "chevron.up" : "chevron.down")
                        .font(AppTheme.typography.sized(11, weight: .bold))
                        .foregroundStyle(sectionSubtitleColor.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, horizontalInset)
                .padding(.top, AppTheme.spacing.md)
                .padding(.bottom, AppTheme.spacing.sm)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("还没有项目")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(emptyStateTitleColor)

            Text("先创建一个项目，再把拆解步骤留在项目层里推进。")
                .foregroundStyle(sectionSubtitleColor)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: Color {
        style == .layer ? AppTheme.colors.projectLayerSurface.opacity(0.12) : .clear
    }

    private var emptyStateTitleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerText : AppTheme.colors.title
    }

    private var sectionSubtitleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerSecondaryText : AppTheme.colors.body
    }

    private func toggleExpanded(_ projectID: UUID) {
        let targetIsExpanded = expansionState.expandedProjectIDs.contains(projectID) == false
        HomeInteractionFeedback.soft()
        withAnimation(targetIsExpanded ? expandAnimation : collapseAnimation) {
            editingProjectID = nil
            titleDraft = ""
            expansionState.toggle(projectID)
        }
    }

    private func projectChromeOverlay(proxy: GeometryProxy) -> some View {
        ZStack {
            ProjectToolbarBackground()
                .frame(height: projectHeaderProtectionHeight + proxy.safeAreaInsets.top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ProjectToolbarBackground(reverseGradient: true)
                .frame(height: max(94, proxy.safeAreaInsets.bottom + 84))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: isPresented)
    }

    private var projectModeTopProtectionInset: CGFloat {
        showsHeader ? 0 : AppTheme.spacing.xxs
    }

    private var visibleProjectIDs: [UUID] {
        var ids = viewModel.activeProjects.map(\.id)
        if showsArchivedProjects {
            ids.append(contentsOf: viewModel.archivedProjects.map(\.id))
        }
        return ids
    }

    private var datePickerBinding: Binding<Project?> {
        Binding(
            get: {
                guard let id = datePickerProjectID else { return nil }
                return viewModel.projects.first(where: { $0.id == id })
            },
            set: { project in
                datePickerProjectID = project?.id
            }
        )
    }

    private func titleBinding(for projectID: UUID) -> Binding<String> {
        Binding(
            get: { editingProjectID == projectID ? titleDraft : "" },
            set: { titleDraft = $0 }
        )
    }

    private func commitTitle(for projectID: UUID, value: String) async {
        guard let project = viewModel.projects.first(where: { $0.id == projectID }) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != project.name else {
            titleDraft = ""
            return
        }

        var updatedProject = project
        updatedProject.name = trimmed
        await viewModel.updateProject(updatedProject)
        titleDraft = ""
    }

    private func commitTargetDate(for projectID: UUID, value: Date) async {
        guard let project = viewModel.projects.first(where: { $0.id == projectID }) else { return }
        let nextDate = Calendar.current.startOfDay(for: value)
        guard project.targetDate.map({ Calendar.current.isDate($0, inSameDayAs: nextDate) }) != true else { return }

        var updatedProject = project
        updatedProject.targetDate = nextDate
        await viewModel.updateProject(updatedProject)
    }

    private func applyEntryExpansionIfNeeded() {
        guard isPresented else { return }
        guard visibleProjectIDs.isEmpty == false else {
            hasAppliedEntryExpansion = false
            return
        }
        expansionState.resetForEntry(visibleProjectIDs: visibleProjectIDs)
        hasAppliedEntryExpansion = true
    }
}

private struct ProjectDeadlineSheetModifier: ViewModifier {
    let project: Binding<Project?>
    @Binding var stagedTargetDate: Date
    let onDismiss: (Project) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: project) { project in
            ProjectDeadlinePickerSheet(
                selectedDate: Binding(
                    get: { stagedTargetDate },
                    set: { stagedTargetDate = $0 }
                ),
                onDismiss: {
                    onDismiss(project)
                }
            )
            .presentationDetents([.height(TaskEditorDatePickerSheet.preferredHeight + 88)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(AppTheme.colors.surface)
        }
    }
}

private struct ProjectToolbarBackground: View {
    var reverseGradient = false

    var body: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .background(.bar)
            } else {
                ProjectToolbarBlur()
            }

            LinearGradient(
                colors: reverseGradient
                    ? [
                        AppTheme.colors.projectLayerBackground.opacity(0),
                        AppTheme.colors.projectLayerBackground.opacity(0.82)
                    ]
                    : [
                        AppTheme.colors.projectLayerBackground.opacity(0.88),
                        AppTheme.colors.projectLayerBackground.opacity(0)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct ProjectToolbarBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
    }
}

private struct ProjectListRow: View {
    let project: Project
    let style: ProjectsPresentationStyle
    let isExpanded: Bool
    let isEditingTitle: Bool
    let animationBatch: Int
    @Binding var titleDraft: String
    let onToggleExpanded: () -> Void
    let onToggleCompletion: () -> Void
    let onToggleSubtask: (UUID) -> Void
    let onUpdateSubtask: (UUID, String) -> Void
    let onAddSubtask: (String) -> Void
    let onBeginTitleEditing: () -> Void
    let onCommitTitle: (String) -> Void
    let onOpenDeadlineEditor: () -> Void
    let onSubtitleTapped: () -> Void
    let onRequestAddSubtask: () -> Void
    @FocusState private var isTitleFieldFocused: Bool
    private let horizontalInset = AppTheme.spacing.xl
    private let expandedStateAnimation = Animation.snappy(duration: 0.42, extraBounce: 0.06)
    private let collapseStateAnimation = Animation.snappy(duration: 0.28, extraBounce: 0)
    private let subtaskAnimation = Animation.smooth(duration: 0.22).delay(0.04)
    private var canExpandInteractions: Bool {
        project.status != .completed
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            Button(action: onToggleCompletion) {
                ProjectCompletionBadge(isCompleted: project.status == .completed)
                    .frame(width: 40, height: 40)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if project.status == .completed {
                        HomeInteractionFeedback.selection()
                    } else {
                        HomeInteractionFeedback.completion()
                    }
                }
            )
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                HStack(alignment: .top, spacing: AppTheme.spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                        titleRegion
                        subtitleAction
                    }

                    Spacer(minLength: 0)

                    deadlineEditorButton
                }

                if isExpanded {
                    ProjectSubtasksSection(
                        project: project,
                        style: style,
                        animationBatch: animationBatch,
                        shouldFocusInput: project.subtasks.isEmpty,
                        onToggleSubtask: onToggleSubtask,
                        onUpdateSubtask: onUpdateSubtask,
                        onAddSubtask: onAddSubtask
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        )
                    )
                    .animation(subtaskAnimation, value: isExpanded)
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, AppTheme.spacing.md)
        .contentShape(Rectangle())
        .animation(isExpanded ? expandedStateAnimation : collapseStateAnimation, value: isExpanded)
        .onChange(of: project.name) { _, newValue in
            if isEditingTitle == false {
                titleDraft = newValue
            }
        }
        .onChange(of: isEditingTitle) { _, isEditing in
            if isEditing {
                titleDraft = project.name
                isTitleFieldFocused = true
            } else {
                isTitleFieldFocused = false
            }
        }
    }

    private var titleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerText : AppTheme.colors.title
    }

    private var titleFont: Font {
        AppTheme.typography.sized(19, weight: .bold)
    }

    private var subtitleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerSecondaryText : AppTheme.colors.body.opacity(0.68)
    }

    private var subtitleActionTextColor: Color {
        subtitleColor
    }

    private var deadlineColor: Color {
        if project.status == .completed {
            return subtitleColor.opacity(0.74)
        }
        return style == .layer ? AppTheme.colors.projectLayerText : AppTheme.colors.timeText.opacity(0.82)
    }

    private var progressTint: Color { AppTheme.colors.coral }

    private var subtitleActionText: String {
        guard project.subtasks.isEmpty == false else { return "添加子任务" }
        if project.completedSubtaskCount == 0 {
            return "\(project.subtasks.count) 个子任务"
        }
        return "\(project.completedSubtaskCount)/\(project.subtasks.count) 已完成"
    }

    private func dueSummary(prefix: String) -> String {
        guard let targetDate = project.targetDate else { return "尚未设置截止日期" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let targetDay = calendar.startOfDay(for: targetDate)
        let dayDelta = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0

        if dayDelta < 0 {
            return "已逾期 \(-dayDelta) 天"
        }
        if dayDelta == 0 {
            return "\(prefix)今天截止"
        }
        if dayDelta == 1 {
            return "\(prefix)明天截止"
        }
        return "\(prefix)\(dayDelta) 天后截止"
    }

    private var deadlineText: String {
        guard let targetDate = project.targetDate else { return "--" }
        let calendar = Calendar.current
        if calendar.isDateInToday(targetDate) {
            return "今天"
        }
        if calendar.isDateInTomorrow(targetDate) {
            return "明天"
        }
        let month = calendar.component(.month, from: targetDate)
        let day = calendar.component(.day, from: targetDate)
        return "\(month)月\(day)日"
    }

    private var isOverdue: Bool {
        guard let targetDate = project.targetDate else { return false }
        return Calendar.current.startOfDay(for: targetDate) < Calendar.current.startOfDay(for: .now)
    }

    @ViewBuilder
    private var titleRegion: some View {
        if isEditingTitle {
            TextField("", text: $titleDraft, prompt: Text(project.name))
                .font(titleFont)
                .foregroundStyle(titleColor)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($isTitleFieldFocused)
                .onSubmit {
                    onCommitTitle(titleDraft)
                }
                .onChange(of: isTitleFieldFocused) { _, focused in
                    if focused == false, isEditingTitle {
                        onCommitTitle(titleDraft)
                    }
                }
        } else {
            Button(action: titleAction) {
                Text(project.name)
                    .font(titleFont)
                    .foregroundStyle(titleColor.opacity(project.status == .completed ? 0.56 : 1))
                    .strikethrough(project.status == .completed, color: subtitleColor.opacity(0.34))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitleAction: some View {
        Button {
            guard canExpandInteractions else { return }
            if isExpanded == false {
                onToggleExpanded()
            } else if project.subtasks.isEmpty {
                onRequestAddSubtask()
            } else {
                onSubtitleTapped()
            }
        } label: {
            HStack(spacing: AppTheme.spacing.xxs) {
                Text(subtitleActionText)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                    .foregroundStyle(subtitleActionTextColor)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(AppTheme.typography.sized(11, weight: .bold))
                    .foregroundStyle(subtitleColor.opacity(0.74))
            }
        }
        .buttonStyle(.plain)
    }

    private var deadlineEditorButton: some View {
        Button(action: deadlineAction) {
            VStack(alignment: .trailing, spacing: AppTheme.spacing.xs) {
                Text(deadlineText)
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(deadlineColor)
                    .multilineTextAlignment(.trailing)

                if project.subtasks.isEmpty == false {
                    HStack(alignment: .center, spacing: AppTheme.spacing.xs) {
                        ProjectProgressBar(progress: project.subtaskProgress, tint: progressTint)

                        Text("\(project.completedSubtaskCount)/\(project.subtasks.count)")
                            .font(AppTheme.typography.sized(12, weight: .semibold))
                            .foregroundStyle(subtitleColor.opacity(0.72))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func titleAction() {
        guard canExpandInteractions else { return }
        if isExpanded {
            onBeginTitleEditing()
        } else {
            onToggleExpanded()
        }
    }

    private func deadlineAction() {
        guard canExpandInteractions else { return }
        onOpenDeadlineEditor()
    }
}

private extension View {
    func projectContextMenu(
        project: Project,
        canDelete: Bool,
        onDelete: @escaping () -> Void
    ) -> some View {
        simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    HomeInteractionFeedback.soft()
                }
        )
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("删除项目", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
    }
}

private struct ProjectDeadlinePickerSheet: View {
    @Binding var selectedDate: Date
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("修改截止日期")
                .font(AppTheme.typography.sized(22, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, AppTheme.spacing.lg)

            TaskEditorDatePickerSheet(
                selectedDate: $selectedDate,
                selectionFeedback: HomeInteractionFeedback.selection,
                onDismiss: onDismiss
            )
            .frame(height: TaskEditorDatePickerSheet.preferredHeight)
            .padding(.bottom, AppTheme.spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.colors.surface)
    }
}

private struct ProjectSubtasksSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: Project
    let style: ProjectsPresentationStyle
    let animationBatch: Int
    let shouldFocusInput: Bool
    let onToggleSubtask: (UUID) -> Void
    let onUpdateSubtask: (UUID, String) -> Void
    let onAddSubtask: (String) -> Void
    @State private var draftTitle = ""
    @State private var editingSubtaskID: UUID?
    @State private var subtaskDraft = ""
    @FocusState private var isInputFocused: Bool
    @FocusState private var focusedSubtaskID: UUID?
    private let verticalSpacing: CGFloat = AppTheme.spacing.sm

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            ForEach(Array(project.subtasks.enumerated()), id: \.element.id) { index, subtask in
                SubtaskCascadeRow(
                    index: index,
                    animationBatch: animationBatch,
                    reduceMotion: reduceMotion
                ) {
                    HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                        SubtaskCheckbox(
                            isCompleted: subtask.isCompleted,
                            onToggle: { onToggleSubtask(subtask.id) }
                        )

                        if editingSubtaskID == subtask.id {
                            TextField("", text: subtaskBinding(for: subtask), prompt: Text(subtask.title))
                                .font(AppTheme.typography.sized(15, weight: .medium))
                                .foregroundStyle(titleColor)
                                .textInputAutocapitalization(.sentences)
                                .submitLabel(.done)
                                .focused($focusedSubtaskID, equals: subtask.id)
                                .onSubmit {
                                    commitSubtask(subtask)
                                }
                                .onChange(of: focusedSubtaskID) { _, focusedID in
                                    if focusedID != subtask.id, editingSubtaskID == subtask.id {
                                        commitSubtask(subtask)
                                    }
                                }
                        } else {
                            Button {
                                HomeInteractionFeedback.selection()
                                editingSubtaskID = subtask.id
                                subtaskDraft = subtask.title
                                focusedSubtaskID = subtask.id
                            } label: {
                                Text(subtask.title)
                                    .font(AppTheme.typography.sized(15, weight: .medium))
                                    .foregroundStyle(titleColor.opacity(subtask.isCompleted ? 0.46 : 0.92))
                                    .strikethrough(subtask.isCompleted, color: subtitleColor.opacity(0.32))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }

            SubtaskCascadeRow(
                index: project.subtasks.count,
                animationBatch: animationBatch,
                reduceMotion: reduceMotion
            ) {
                HStack(spacing: AppTheme.spacing.sm) {
                    Button(action: addSubtask) {
                        Image(systemName: "plus.circle.fill")
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.coral)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HomeInteractionFeedback.selection()
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    TextField("添加子任务", text: $draftTitle)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(titleColor)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($isInputFocused)
                        .onSubmit(addSubtask)
                }
            }
        }
        .padding(.top, verticalSpacing)
        .onAppear {
            if shouldFocusInput {
                Task { @MainActor in
                    isInputFocused = true
                }
            }
        }
        .onChange(of: project.subtasks) { _, subtasks in
            if let editingSubtaskID, subtasks.contains(where: { $0.id == editingSubtaskID }) == false {
                self.editingSubtaskID = nil
                subtaskDraft = ""
            }
        }
    }

    private var titleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerText : AppTheme.colors.title
    }

    private var subtitleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerSecondaryText : AppTheme.colors.body
    }

    private func subtaskBinding(for subtask: ProjectSubtask) -> Binding<String> {
        Binding(
            get: { editingSubtaskID == subtask.id ? subtaskDraft : subtask.title },
            set: { subtaskDraft = $0 }
        )
    }

    private func commitSubtask(_ subtask: ProjectSubtask) {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            editingSubtaskID = nil
            subtaskDraft = ""
            focusedSubtaskID = nil
        }
        guard trimmed.isEmpty == false, trimmed != subtask.title else { return }
        onUpdateSubtask(subtask.id, trimmed)
    }

    private func addSubtask() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        HomeInteractionFeedback.selection()
        onAddSubtask(trimmed)
        draftTitle = ""
    }
}

private struct ProjectProgressBar: View {
    let progress: Double
    let tint: Color
    private let barWidth: CGFloat = 48

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))

            Capsule(style: .continuous)
                .fill(tint)
                .frame(width: progress > 0 ? max(10, barWidth * progress) : 0)
        }
        .frame(width: barWidth, height: 6)
        .animation(.smooth(duration: 0.2), value: progress)
    }
}

struct ProjectExpansionPresentationState {
    private(set) var expandedProjectIDs: Set<UUID> = []
    private(set) var animationBatch = 0

    mutating func resetForEntry(visibleProjectIDs: [UUID]) {
        expandedProjectIDs = []
        animationBatch += 1
    }

    mutating func syncVisibleProjectIDs(_ visibleProjectIDs: [UUID]) {
        let visibleIDs = Set(visibleProjectIDs)
        expandedProjectIDs = expandedProjectIDs.intersection(visibleIDs)
    }

    mutating func toggle(_ projectID: UUID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
        }
    }
}

private struct ProjectCompletionBadge: View {
    let isCompleted: Bool

    @State private var isAnimating = false
    @State private var animationCount = 0
    @State private var badgeScale: CGFloat = 1
    @State private var fillScale: CGFloat = 1
    @State private var fillOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.14))
                .scaleEffect(fillScale)
                .opacity(isCompleted ? 0 : fillOpacity)

            RoundedRectangle(cornerRadius: AppTheme.radius.sm, style: .continuous)
                .strokeBorder(
                    isAnimating ? AppTheme.colors.body.opacity(0.32) : AppTheme.colors.body.opacity(0.44),
                    style: StrokeStyle(lineWidth: isAnimating ? 1.8 : 1.6, dash: [3.6, 4.4])
                )
                .opacity(isCompleted ? 0 : 1)

            Image(systemName: "checkmark")
                .font(AppTheme.typography.sized(17, weight: .bold))
                .foregroundStyle(AppTheme.colors.coral)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.15), value: animationCount)
                .opacity(isCompleted ? 1 : 0)
                .offset(
                    x: AppTheme.metrics.checkmarkVisualOffset.width,
                    y: AppTheme.metrics.checkmarkVisualOffset.height
                )
        }
        .scaleEffect(isAnimating ? badgeScale : 1)
        .shadow(
            color: AppTheme.colors.coral.opacity(isAnimating ? 0.2 : 0),
            radius: isAnimating ? 12 : 0,
            y: isAnimating ? 5 : 0
        )
        .onChange(of: isCompleted) { _, newValue in
            guard newValue else { return }
            triggerAnimation()
        }
    }

    private func triggerAnimation() {
        animationCount += 1
        isAnimating = true
        fillScale = 1; fillOpacity = 0
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
            badgeScale = 1.22; fillScale = 1.4; fillOpacity = 1
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.52).delay(0.1)) {
            badgeScale = 1; fillOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isAnimating = false; fillScale = 1
        }
    }
}

// SubtaskCheckbox and SubtaskCascadeRow are in Features/Shared/SubtaskComponents.swift

private struct AnimatedProjectCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.22))
        return path
    }
}

private struct ProjectCascadeItem<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: ProjectCascadePhase = .hidden
    @State private var animationTask: Task<Void, Never>?

    let isVisible: Bool
    let index: Int
    @ViewBuilder let content: Content

    init(
        isVisible: Bool,
        index: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.isVisible = isVisible
        self.index = index
        self.content = content()
    }

    var body: some View {
        content
            .opacity(phase.opacity)
            .offset(y: phase.offsetY)
            .scaleEffect(phase.scale, anchor: .center)
            .animation(animation(for: phase), value: phase)
            .onAppear {
                updatePhase(for: isVisible)
            }
            .onChange(of: isVisible) { _, visible in
                updatePhase(for: visible)
            }
            .onDisappear {
                animationTask?.cancel()
            }
    }

    private func updatePhase(for visible: Bool) {
        animationTask?.cancel()

        guard visible else {
            phase = .hidden
            return
        }

        let delay = Double(index) * 0.034
        phase = .hidden

        animationTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            phase = .preparing
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 70 : 95))
            guard !Task.isCancelled else { return }
            phase = .settled
        }
    }

    private func animation(for phase: ProjectCascadePhase) -> Animation {
        if reduceMotion {
            switch phase {
            case .hidden:
                return .easeOut(duration: 0.12)
            case .preparing:
                return .easeOut(duration: 0.10)
            case .settled:
                return .easeOut(duration: 0.16)
            }
        }

        switch phase {
        case .hidden:
            return .easeOut(duration: 0.14)
        case .preparing:
            return .easeOut(duration: 0.12)
        case .settled:
            return .spring(response: 0.34, dampingFraction: 0.9)
        }
    }
}

private enum ProjectCascadePhase: CaseIterable {
    case hidden
    case preparing
    case settled

    var opacity: Double {
        switch self {
        case .hidden:
            return 0.02
        case .preparing:
            return 0.68
        case .settled:
            return 1
        }
    }

    var offsetY: CGFloat {
        switch self {
        case .hidden:
            return 28
        case .preparing:
            return 10
        case .settled:
            return 0
        }
    }

    var scale: CGFloat {
        switch self {
        case .hidden:
            return 0.992
        case .preparing:
            return 0.998
        case .settled:
            return 1
        }
    }
}

private extension ProjectStatus {
    var badgeTitle: String {
        switch self {
        case .active:
            return "进行中"
        case .onHold:
            return "暂停"
        case .completed:
            return "已完成"
        case .archived:
            return "已归档"
        }
    }

    var tint: Color {
        switch self {
        case .active:
            return AppTheme.colors.accent
        case .onHold:
            return AppTheme.colors.warning
        case .completed:
            return AppTheme.colors.success
        case .archived:
            return AppTheme.colors.body
        }
    }
}
