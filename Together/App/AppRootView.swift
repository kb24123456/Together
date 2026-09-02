import PhotosUI
import SwiftUI

private enum AppRootRoute: Hashable {
    case profile
    case completedHistory(CompletedHistoryFilter)
    case planningReview
}

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        HomeRootContent()
            .environment(appContext)
            .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
    }
}

struct HomeRootContent: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rootNavigationPath = NavigationPath()
    @State private var activeOCRSourceSession: OCRSourceSheetSession?
    @State private var pendingOCRReviewSession: OCRReviewSession?
    @State private var isPresentingDirectOCRPhotoPicker = false
    @State private var directOCRPhotoPickerSelection: [PhotosPickerItem] = []
    @State private var directOCRProcessingTask: Task<Void, Never>?
    @State private var isPresentingDirectOCRCamera = false
    @State private var taskCreationDestination: TaskCreationDestination?
    @State private var pendingCreatedTaskReveal: TaskCreationDestination?
    @State private var activeTaskDetailPresentation: TaskDetailPresentation?
    @State private var isWeeklyReviewMenuPresented = false
    @State private var weeklyReviewMenuSourceFrame: CGRect = .zero
    @AccessibilityFocusState private var weeklyReviewMenuFocus: HomeWeeklyReviewMenuFocus?
    @Namespace private var taskCreationTransition
    @Namespace private var taskDetailTransition

    private var displayedRootSurface: RootSurface {
        appContext.router.currentSurface
    }

    private var isHomeSurfaceVisible: Bool {
        rootNavigationPath.isEmpty
            && activeTaskDetailPresentation == nil
            && activeOCRSourceSession == nil
            && pendingOCRReviewSession == nil
            && appContext.router.activeOCRReviewSession == nil
            && isPresentingDirectOCRPhotoPicker == false
            && isPresentingDirectOCRCamera == false
            && taskCreationDestination == nil
    }

    var body: some View {
        @Bindable var router = appContext.router

        ZStack {
            NavigationStack(path: $rootNavigationPath) {
                rootSurfaceView(router: router)
                    .allowsHitTesting(activeTaskDetailPresentation == nil)
                    .toolbar {
                        if #available(iOS 26.0, *) {
                            topToolbar(router: router)
                                .sharedBackgroundVisibility(.hidden)
                        } else {
                            topToolbar(router: router)
                        }

                        bottomToolbar(router: router)
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: AppRootRoute.self) { route in
                        switch route {
                        case .profile:
                            ProfileView(viewModel: appContext.profileViewModel)
                        case .completedHistory(let filter):
                            CompletedHistoryView(
                                viewModel: appContext.profileViewModel.makeCompletedHistoryViewModel(initialFilter: filter)
                            )
                        case .planningReview:
                            PlanningReviewView(
                                loadReview: appContext.profileViewModel.planningReview,
                                loadTaskReview: appContext.profileViewModel.taskLifecycleReview
                            )
                        }
                    }
            }
            .accessibilityHidden(isWeeklyReviewMenuPresented)

            weeklyReviewMenuOverlay
                .zIndex(20)
        }
        .background(Color.clear)
        .sheet(item: $activeOCRSourceSession, onDismiss: {
            guard let pendingOCRReviewSession else { return }
            router.activeOCRReviewSession = pendingOCRReviewSession
            self.pendingOCRReviewSession = nil
        }) { session in
            OCRSourceSheet(
                session: session,
                onReviewReady: { completedSession in
                    pendingOCRReviewSession = OCRReviewSession(
                        viewModel: completedSession.viewModel,
                        availableHeight: completedSession.availableHeight
                    )
                    activeOCRSourceSession = nil
                },
                onRetryCamera: {
                    activeOCRSourceSession = nil
                    isPresentingDirectOCRCamera = true
                }
            )
        }
        .sheet(item: $router.activeOCRReviewSession) { session in
            OCRReviewSheet(
                session: session,
                appContext: appContext
            )
        }
        .photosPicker(
            isPresented: $isPresentingDirectOCRPhotoPicker,
            selection: $directOCRPhotoPickerSelection,
            maxSelectionCount: 6,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: directOCRPhotoPickerSelection) { _, newValue in
            loadDirectOCRPhotos(from: newValue)
        }
        .fullScreenCover(isPresented: $isPresentingDirectOCRCamera) {
            OCRNativeCameraPicker(
                onCapture: { image in
                    isPresentingDirectOCRCamera = false
                    handleDirectOCRCapture(image)
                },
                onCancel: {
                    isPresentingDirectOCRCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $activeTaskDetailPresentation) { presentation in
            taskDetailView(presentation: presentation)
        }
        .fullScreenCover(item: $taskCreationDestination, onDismiss: revealCreatedTaskIfNeeded) { destination in
            taskCreationView(destination: destination)
        }
        .environment(\.symbolVariants, .none)
        .font(AppTheme.typography.body)
        .tint(AppTheme.colors.title)
        .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
        .onChange(of: router.isProfilePresented) { _, isPresented in
            guard isPresented else { return }
            guard rootNavigationPath.count == 0 else { return }
            rootNavigationPath.append(AppRootRoute.profile)
        }
        .onChange(of: rootNavigationPath.count) { _, count in
            if count == 0 {
                router.isProfilePresented = false
            }
        }
        .onChange(of: router.rootResetRevision) { _, _ in
            rootNavigationPath = NavigationPath()
        }
        .onChange(of: router.composerRequestRevision) { _, _ in
            synchronizeComposerPresentation(router: router)
        }
        .onAppear {
            synchronizeComposerPresentation(router: router)
        }
        .task {
            StartupTrace.mark("AppRootView.visible")
        }
    }

    @ViewBuilder
    private func rootSurfaceView(router: AppRouter) -> some View {
        HomeView(
            viewModel: appContext.homeViewModel,
            routinesViewModel: appContext.routinesViewModel,
            isRoutinesModePresented: displayedRootSurface == .routines,
            isRootSurfaceVisible: isHomeSurfaceVisible,
            isWeeklyReviewMenuPresented: $isWeeklyReviewMenuPresented,
            weeklyReviewMenuSourceFrame: $weeklyReviewMenuSourceFrame,
            weeklyReviewMenuFocus: $weeklyReviewMenuFocus,
            onCreateTaskTapped: {
                presentTaskCreation(domain: .todo)
            },
            taskDetailTransition: taskDetailTransition,
            onOpenTaskDetail: openTaskDetail,
            onCompletedHistoryTapped: { filter in
                rootNavigationPath.append(AppRootRoute.completedHistory(filter))
            }
        )
    }

    private var weeklyReviewMenuOverlay: some View {
        GeometryReader { proxy in
            let containerFrame = proxy.frame(in: .global)
            let menuWidth = HomeWeeklyReviewMenuLayout.actionWidth(
                containerWidth: proxy.size.width,
                usesAccessibilityLayout: dynamicTypeSize.isAccessibilitySize
            )
            let menuOrigin = HomeWeeklyReviewMenuLayout.actionOrigin(
                sourceFrame: weeklyReviewMenuSourceFrame,
                containerFrame: containerFrame,
                containerWidth: proxy.size.width,
                actionWidth: menuWidth
            )

            ZStack(alignment: .topLeading) {
                weeklyReviewMenuBackdrop

                if weeklyReviewMenuSourceFrame != .zero {
                    weeklyReviewSpeedDialActions
                        .frame(width: menuWidth)
                        .offset(x: menuOrigin.x, y: menuOrigin.y)
                        .zIndex(1)
                }
            }
        }
        .allowsHitTesting(isWeeklyReviewMenuPresented)
        .accessibilityHidden(!isWeeklyReviewMenuPresented)
    }

    @ViewBuilder
    private var weeklyReviewMenuBackdrop: some View {
        if reduceMotion || reduceTransparency {
            Color(uiColor: .systemBackground)
                .opacity(isWeeklyReviewMenuPresented ? 0.86 : 0)
                .animation(weeklyReviewMenuAnimation, value: isWeeklyReviewMenuPresented)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissWeeklyReviewMenu(restoresAccessibilityFocus: true)
                }
                .ignoresSafeArea()
        } else {
            Rectangle()
                .fill(.thinMaterial)
                .opacity(isWeeklyReviewMenuPresented ? 0.45 : 0)
                .animation(weeklyReviewMenuAnimation, value: isWeeklyReviewMenuPresented)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissWeeklyReviewMenu(restoresAccessibilityFocus: true)
                }
                .ignoresSafeArea()
        }
    }

    private var weeklyReviewSpeedDialActions: some View {
        VStack(alignment: .trailing, spacing: HomeWeeklyReviewMenuLayout.rowSpacing) {
            weeklyReviewSpeedDialRow(
                index: 0,
                title: "本周已完成"
            ) {
                dismissWeeklyReviewMenu(restoresAccessibilityFocus: false)
                HomeInteractionFeedback.selection()
                Task {
                    await appContext.homeViewModel.presentWeeklyCompletedSheet()
                }
            }
            .accessibilityFocused($weeklyReviewMenuFocus, equals: .completed)

            weeklyReviewSpeedDialRow(
                index: 1,
                title: "计划复盘"
            ) {
                dismissWeeklyReviewMenu(restoresAccessibilityFocus: false)
                HomeInteractionFeedback.selection()
                rootNavigationPath.append(AppRootRoute.planningReview)
            }
            .accessibilityFocused($weeklyReviewMenuFocus, equals: .planningReview)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("本周回顾菜单")
    }

    private func weeklyReviewSpeedDialRow(
        index: Int,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.scaled(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(AppTheme.colors.title)
                .fontDesign(.rounded)
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: weeklyReviewMenuRowHeight,
                    alignment: .trailing
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeWeeklyReviewMenuRowButtonStyle(reduceMotion: reduceMotion))
        .opacity(isWeeklyReviewMenuPresented ? 1 : 0)
        .scaleEffect(
            reduceMotion || isWeeklyReviewMenuPresented ? 1 : 0.42,
            anchor: .trailing
        )
        .offset(
            y: isWeeklyReviewMenuPresented
                ? 0
                : -CGFloat(index) * (weeklyReviewMenuRowHeight + HomeWeeklyReviewMenuLayout.rowSpacing)
        )
        .animation(weeklyReviewMenuItemAnimation, value: isWeeklyReviewMenuPresented)
        .zIndex(Double(2 - index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("打开\(title)")
    }

    private var weeklyReviewMenuRowHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 56 : HomeWeeklyReviewMenuLayout.rowHeight
    }

    private var weeklyReviewMenuItemAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.14)
            : .smooth(duration: 0.27, extraBounce: 0)
    }

    private var weeklyReviewMenuAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.14)
            : .smooth(duration: 0.22, extraBounce: 0)
    }

    private func dismissWeeklyReviewMenu(restoresAccessibilityFocus: Bool) {
        guard isWeeklyReviewMenuPresented else { return }
        isWeeklyReviewMenuPresented = false
        if restoresAccessibilityFocus {
            weeklyReviewMenuFocus = .trigger
        }
    }

    // MARK: - Navigation toolbars

    @ToolbarContentBuilder
    private func topToolbar(router: AppRouter) -> some ToolbarContent {
        let showsModePicker = appContext.sessionStore.activeMode == .single
        let isRoutinesModeActive = displayedRootSurface == .routines

        ToolbarItem(placement: .principal) {
            ZStack {
                if showsModePicker {
                    if dynamicTypeSize.isAccessibilitySize {
                        Menu {
                            Picker("任务模式", selection: rootModeSelection(router: router)) {
                                Text("待办").tag(RootSurface.today)
                                Text("定期").tag(RootSurface.routines)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isRoutinesModeActive ? "定期" : "待办")
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.headline)
                            .foregroundStyle(AppTheme.colors.title)
                        }
                        .accessibilityIdentifier("together.mode-picker")
                        .accessibilityLabel("任务模式")
                        .accessibilityValue(isRoutinesModeActive ? "定期任务" : "待办任务")
                        .accessibilityHint("选择待办或定期模式")
                    } else {
                        HStack(spacing: 0) {
                            rootModeButton(
                                title: "待办",
                                surface: .today,
                                isSelected: isRoutinesModeActive == false,
                                router: router
                            )
                            rootModeButton(
                                title: "定期",
                                surface: .routines,
                                isSelected: isRoutinesModeActive,
                                router: router
                            )
                        }
                        .frame(width: 144, height: 44)
                        .accessibilityIdentifier("together.mode-picker")
                    }
                } else {
                    Text("待办")
                        .font(.headline)
                        .foregroundStyle(AppTheme.colors.title)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HomeInteractionFeedback.selection()
                openProfile(router: router)
            } label: {
                let avatar = appContext.homeViewModel.currentUserAvatar
                UserAvatarView(
                    avatarAsset: avatar.avatarAsset,
                    displayName: avatar.displayName,
                    size: 40,
                    fillColor: AppTheme.colors.avatarWarm,
                    symbolColor: AppTheme.colors.title.opacity(0.82),
                    symbolFont: AppTheme.typography.sized(18, weight: .semibold),
                    overrideImage: avatar.overrideImage
                )
                .overlay {
                    Circle()
                        .strokeBorder(AppTheme.colors.hairline, lineWidth: 0.5)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开个人页")
            .accessibilityHint("查看个人资料和设置")
        }
    }

    @ToolbarContentBuilder
    private func bottomToolbar(router: AppRouter) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Menu {
                Button(action: openDirectOCRCamera) {
                    Label("相机", systemImage: "camera")
                }
                Button(action: openDirectOCRPhotoPicker) {
                    Label("照片", systemImage: "photo.on.rectangle")
                }
                Button(action: openDirectOCRTextPaste) {
                    Label("粘贴文字", systemImage: "doc.on.clipboard")
                }
            } label: {
                Label("OCR 导入", systemImage: "doc.text.viewfinder")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("together.bottom-toolbar.ocr")
            .accessibilityHint("拍摄、选择照片或粘贴多行文字生成草稿")
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                HomeInteractionFeedback.selection()
                openContextualComposer(router: router)
            } label: {
                Label("新建", systemImage: "plus")
                .labelStyle(.iconOnly)
            }
            .matchedTransitionSource(
                id: TaskCreationTransitionSource.addButton,
                in: taskCreationTransition
            )
            .accessibilityIdentifier("together.bottom-toolbar.add")
            .accessibilityHint("在当前视图下新建一项")
        }
    }

    private func rootModeButton(
        title: String,
        surface: RootSurface,
        isSelected: Bool,
        router: AppRouter
    ) -> some View {
        Button {
            selectRootSurface(surface, router: router)
        } label: {
            HomeModeSelectionLabel(
                title: title,
                isSelected: isSelected
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeModePlainButtonStyle())
        .frame(width: 72, height: 44)
        .accessibilityIdentifier("together.mode-picker.\(surface == .today ? "today" : "routines")")
        .accessibilityLabel("\(title)任务")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "当前模式" : "切换到\(title)任务")
    }

    // MARK: - Surface routing

    private var rootModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private func openProfile(router: AppRouter) {
        guard router.isProfilePresented == false else { return }
        router.isProfilePresented = true
    }

    private func openContextualComposer(router: AppRouter) {
        switch displayedRootSurface {
        case .today:
            presentTaskCreation(domain: .todo)
        case .routines:
            presentTaskCreation(domain: .periodic)
        }
    }

    private func openTaskDetail(_ route: TaskDetailRoute) {
        guard rootNavigationPath.isEmpty,
              taskCreationDestination == nil,
              activeTaskDetailPresentation == nil
        else { return }

        let didPrepare: Bool
        switch route {
        case .todo(let id):
            guard appContext.homeViewModel.timelineEntry(for: id)?.isCompleted == false else { return }
            appContext.homeViewModel.presentItemDetail(id)
            appContext.homeViewModel.markDetailForExpandedEditing()
            didPrepare = appContext.homeViewModel.selectedItemID == id
        case .periodic(let id):
            didPrepare = appContext.routinesViewModel.presentDetailForMorph(id)
        }

        guard didPrepare else { return }
        let presentation = TaskDetailPresentation(route: route)
        activeTaskDetailPresentation = presentation
        HomeInteractionFeedback.soft()
    }

    @ViewBuilder
    private func taskDetailView(presentation: TaskDetailPresentation) -> some View {
        let route = presentation.route
        let detail = TaskDetailView(
            presentation: presentation,
            homeViewModel: appContext.homeViewModel,
            routinesViewModel: appContext.routinesViewModel,
            onDidDisappear: finishTaskDetailPresentation
        )

        if reduceMotion {
            detail.navigationTransition(.automatic)
        } else {
            detail.navigationTransition(
                .zoom(
                    sourceID: route,
                    in: taskDetailTransition
                )
            )
        }
    }

    @MainActor
    private func finishTaskDetailPresentation(
        _ presentation: TaskDetailPresentation
    ) {
        guard ownsTaskDetailDraft(for: presentation) else { return }
        releaseTaskDetailPresentation(presentation)
    }

    @MainActor
    private func releaseTaskDetailPresentation(_ presentation: TaskDetailPresentation) {
        guard ownsTaskDetailDraft(for: presentation) else { return }

        switch presentation.route {
        case .todo:
            appContext.homeViewModel.dismissItemDetail()
        case .periodic:
            appContext.routinesViewModel.finishMorphDetail()
        }
        if activeTaskDetailPresentation?.id == presentation.id {
            activeTaskDetailPresentation = nil
        }
    }

    private func ownsTaskDetailDraft(for presentation: TaskDetailPresentation) -> Bool {
        guard presentation.canReleaseSharedDraft(
            while: activeTaskDetailPresentation
        ) else { return false }

        return switch presentation.route {
        case .todo(let id):
            appContext.homeViewModel.selectedItemID == id
        case .periodic(let id):
            appContext.routinesViewModel.expandedTaskID == id
        }
    }

    private func presentTaskCreation(
        domain: TaskMorphDomain,
        title: String? = nil
    ) {
        guard taskCreationDestination == nil else { return }
        switch domain {
        case .todo:
            appContext.homeViewModel.beginTaskCreation()
            if let title, title.isEmpty == false {
                appContext.homeViewModel.updateTaskCreationDraft { $0.title = title }
            }
            guard let session = appContext.homeViewModel.taskCreationSession else { return }
            taskCreationDestination = .todo(session.id)
        case .periodic:
            appContext.routinesViewModel.beginTaskCreation(
                defaultCycle: appContext.router.pendingPeriodicCycle ?? appContext.routinesViewModel.selectedCycle
            )
            if let title, title.isEmpty == false {
                appContext.routinesViewModel.updateCreationDraft { $0.title = title }
            }
            guard let session = appContext.routinesViewModel.creationSession else { return }
            taskCreationDestination = .periodic(session.id)
        }
    }

    private func synchronizeComposerPresentation(router: AppRouter) {
        guard let route = router.activeComposer else { return }

        guard taskCreationDestination == nil else {
            router.clearComposerRequest()
            return
        }
        let title = router.pendingComposerTitle
        router.clearComposerRequest()
        switch route {
        case .newTask:
            presentTaskCreation(domain: .todo, title: title)
        case .newPeriodicTask:
            presentTaskCreation(domain: .periodic, title: title)
        }
    }

    @ViewBuilder
    private func taskCreationView(destination: TaskCreationDestination) -> some View {
        if reduceMotion {
            TaskCreationView(
                destination: destination,
                homeViewModel: appContext.homeViewModel,
                routinesViewModel: appContext.routinesViewModel,
                onCancel: { taskCreationDestination = nil },
                onCreated: completeTaskCreation
            )
            .navigationTransition(.automatic)
        } else {
            TaskCreationView(
                destination: destination,
                homeViewModel: appContext.homeViewModel,
                routinesViewModel: appContext.routinesViewModel,
                onCancel: { taskCreationDestination = nil },
                onCreated: completeTaskCreation
            )
            .navigationTransition(
                .zoom(
                    sourceID: TaskCreationTransitionSource.addButton,
                    in: taskCreationTransition
                )
            )
        }
    }

    private func completeTaskCreation(domain: TaskMorphDomain, id: UUID) {
        pendingCreatedTaskReveal = switch domain {
        case .todo:
            .todo(id)
        case .periodic:
            .periodic(id)
        }
        taskCreationDestination = nil
    }

    private func revealCreatedTaskIfNeeded() {
        guard let pendingCreatedTaskReveal else {
            // Interactive dismissal is equivalent to the explicit cancel action.
            appContext.homeViewModel.discardTaskCreation()
            appContext.routinesViewModel.discardTaskCreation()
            return
        }
        self.pendingCreatedTaskReveal = nil
        switch pendingCreatedTaskReveal {
        case .todo(let id):
            appContext.homeViewModel.revealCommittedTaskCreation(id)
        case .periodic(let id):
            appContext.routinesViewModel.revealCommittedTaskCreation(id)
        }
    }

    private func openDirectOCRPhotoPicker() {
        HomeInteractionFeedback.selection()
        directOCRProcessingTask?.cancel()
        directOCRPhotoPickerSelection = []
        isPresentingDirectOCRPhotoPicker = true
    }

    private func openDirectOCRCamera() {
        HomeInteractionFeedback.selection()
        directOCRProcessingTask?.cancel()
        isPresentingDirectOCRCamera = true
    }

    private func openDirectOCRTextPaste() {
        HomeInteractionFeedback.selection()
        directOCRProcessingTask?.cancel()
        activeOCRSourceSession = OCRSourceSheetSession(source: .pasteText)
    }

    private func handleDirectOCRCapture(_ image: UIImage) {
        directOCRProcessingTask?.cancel()
        directOCRProcessingTask = Task { @MainActor in
            let viewModel = OCRImportViewModel()
            await viewModel.processImages([image])
            switch viewModel.flowState {
            case .review:
                appContext.router.activeOCRReviewSession = OCRReviewSession(
                    viewModel: viewModel,
                    availableHeight: OCRWindowMetrics.availableHeight
                )
            case .failed:
                activeOCRSourceSession = OCRSourceSheetSession(viewModel: viewModel)
            default:
                break
            }
        }
    }

    private func loadDirectOCRPhotos(from items: [PhotosPickerItem]) {
        guard items.isEmpty == false else { return }
        directOCRPhotoPickerSelection = []
        directOCRProcessingTask?.cancel()
        directOCRProcessingTask = Task { @MainActor in
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            guard images.isEmpty == false else { return }
            let viewModel = OCRImportViewModel()
            await viewModel.processImages(images)
            switch viewModel.flowState {
            case .review:
                appContext.router.activeOCRReviewSession = OCRReviewSession(
                    viewModel: viewModel,
                    availableHeight: OCRWindowMetrics.availableHeight
                )
            case .failed:
                activeOCRSourceSession = OCRSourceSheetSession(viewModel: viewModel)
            default:
                break
            }
        }
    }

    private func rootModeSelection(router: AppRouter) -> Binding<RootSurface> {
        Binding(
            get: {
                displayedRootSurface == .routines ? .routines : .today
            },
            set: { surface in
                selectRootSurface(surface, router: router)
            }
        )
    }

    private func selectRootSurface(_ surface: RootSurface, router: AppRouter) {
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }
        guard surface == .today || surface == .routines else { return }
        guard router.currentSurface != surface else { return }

        HomeInteractionFeedback.selection()

        withAnimation(rootModeAnimation) {
            router.currentSurface = surface
        }
    }

}

private struct HomeModeSelectionLabel: View {
    let title: String
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Metrics {
        static let inactiveFontSize: CGFloat = 17
        static let activeFontSize: CGFloat = 21.5
        static let transitionDuration = 0.26

        static let inactiveHiddenScale = activeFontSize / inactiveFontSize
        static let activeHiddenScale = inactiveFontSize / activeFontSize
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(
                    AppTheme.typography.scaled(
                        Metrics.inactiveFontSize,
                        weight: .regular,
                        relativeTo: .headline
                    )
                )
                .foregroundStyle(AppTheme.colors.textTertiary)
                .scaleEffect(inactiveScale)
                .opacity(isSelected ? 0 : 1)

            Text(title)
                .font(
                    AppTheme.typography.scaled(
                        Metrics.activeFontSize,
                        weight: .bold,
                        relativeTo: .headline
                    )
                )
                .foregroundStyle(AppTheme.colors.title)
                .scaleEffect(activeScale)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(selectionAnimation, value: isSelected)
    }

    private var inactiveScale: CGFloat {
        guard reduceMotion == false else { return 1 }
        return isSelected ? Metrics.inactiveHiddenScale : 1
    }

    private var activeScale: CGFloat {
        guard reduceMotion == false else { return 1 }
        return isSelected ? 1 : Metrics.activeHiddenScale
    }

    private var selectionAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.16)
            : .smooth(duration: Metrics.transitionDuration, extraBounce: 0)
    }
}

private struct HomeModePlainButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(pressAnimation(isPressed: configuration.isPressed), value: configuration.isPressed)
    }

    private func pressAnimation(isPressed: Bool) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.08)
        }
        return isPressed
            ? .easeOut(duration: 0.09)
            : .smooth(duration: 0.18, extraBounce: 0)
    }
}
