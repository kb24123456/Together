import PhotosUI
import SwiftUI

private enum AppRootRoute: Hashable {
    case profile
    case completedHistory(CompletedHistoryFilter)
}

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @State private var morphSession = HomeMorphSession()

    var body: some View {
        ZStack {
            HomeRootContent(morphSession: morphSession)
                .environment(appContext)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .accessibilityHidden(morphSession.isCreationOverlayVisible)

            HomeCreationMorphOverlayLayer(session: morphSession)
                .environment(appContext)
        }
        .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
    }
}

struct HomeRootContent: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var morphSession: HomeMorphSession
    @State private var rootNavigationPath = NavigationPath()
    @State private var activeOCRSourceSession: OCRSourceSheetSession?
    @State private var pendingOCRReviewSession: OCRReviewSession?
    @State private var isPresentingDirectOCRPhotoPicker = false
    @State private var directOCRPhotoPickerSelection: [PhotosPickerItem] = []
    @State private var directOCRProcessingTask: Task<Void, Never>?
    @State private var isPresentingDirectOCRCamera = false
    @State private var frozenRootSurface: RootSurface?
    @State private var detailCollapseCompletionTask: Task<Void, Never>?

    private var displayedRootSurface: RootSurface {
        frozenRootSurface ?? appContext.router.currentSurface
    }

    private var isMorphBackgroundDeemphasized: Bool {
        morphSession.isDetailFocusDepthActive
    }

    private var isHomeSurfaceVisible: Bool {
        rootNavigationPath.isEmpty
            && activeOCRSourceSession == nil
            && pendingOCRReviewSession == nil
            && appContext.router.activeOCRReviewSession == nil
            && isPresentingDirectOCRPhotoPicker == false
            && isPresentingDirectOCRCamera == false
    }

    var body: some View {
        @Bindable var router = appContext.router

        NavigationStack(path: $rootNavigationPath) {
            rootSurfaceView(router: router)
                .toolbar {
                    if #available(iOS 26.0, *) {
                        topToolbar(router: router)
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        topToolbar(router: router)
                    }

                    if rootNavigationPath.isEmpty {
                        bottomToolbar(router: router)
                    }
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
                    }
                }
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
        .environment(\.symbolVariants, .none)
        .font(AppTheme.typography.body)
        .tint(AppTheme.colors.title)
        .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
        .onChange(of: router.isProfilePresented) { _, isPresented in
            guard isPresented else { return }
            guard morphSession.isActive == false else {
                morphSession.requestDismissal()
                return
            }
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
        .onChange(of: router.activeComposer?.id) { _, _ in
            synchronizeComposerPresentation(router: router)
        }
        .onChange(of: morphSession.phase) { _, phase in
            switch phase {
            case .active, .saving, .collapsing, .relocating:
                if frozenRootSurface == nil {
                    frozenRootSurface = router.currentSurface
                }
            case .idle:
                frozenRootSurface = nil
                synchronizePendingRootRoutes(router: router)
            }
        }
        .onAppear {
            configureMorphCallbacks()
            synchronizeComposerPresentation(router: router)
        }
        .onDisappear {
            detailCollapseCompletionTask?.cancel()
            morphSession.onDismissIntent = nil
            morphSession.onCommitIntent = nil
            morphSession.onCompletionIntent = nil
            morphSession.onCreationRevealCompletionIntent = nil
            morphSession.onDetailCollapseCompletionIntent = nil
        }
        .task {
            StartupTrace.mark("AppRootView.visible")
        }
    }

    @ViewBuilder
    private func rootSurfaceView(router: AppRouter) -> some View {
        HomeView(
            viewModel: appContext.homeViewModel,
            morphSession: morphSession,
            projectsViewModel: appContext.projectsViewModel,
            routinesViewModel: appContext.routinesViewModel,
            isProjectModePresented: false,
            isRoutinesModePresented: displayedRootSurface == .routines,
            isRootSurfaceVisible: isHomeSurfaceVisible,
            onCreateTaskTapped: {
                router.pendingComposerTitle = nil
                beginMorphCreation(domain: .todo)
            },
            onCompletedHistoryTapped: { filter in
                rootNavigationPath.append(AppRootRoute.completedHistory(filter))
            }
        )
        .task(id: router.currentSurface) {
            guard router.currentSurface == .projects else { return }
            router.currentSurface = .today
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
            .taskMorphBackgroundDepth(
                isDeemphasized: isMorphBackgroundDeemphasized,
                anchor: .top,
                scalesContent: false,
                appliesVisualDepth: false,
                actsAsDismissTarget: morphSession.isCreationFlow == false,
                onDismiss: morphSession.requestDismissal
            )
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
            .taskMorphBackgroundDepth(
                isDeemphasized: isMorphBackgroundDeemphasized,
                anchor: .topTrailing,
                scalesContent: false,
                appliesVisualDepth: false,
                actsAsDismissTarget: morphSession.isCreationFlow == false,
                onDismiss: morphSession.requestDismissal
            )
        }
    }

    @ToolbarContentBuilder
    private func bottomToolbar(router: AppRouter) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            if isMorphBackgroundDeemphasized {
                Button(action: morphSession.requestDismissal) {
                    Label("收起任务详情", systemImage: "doc.text.viewfinder")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("together.bottom-toolbar.ocr")
                .accessibilityHint("保存更改并收起当前任务")
            } else {
                Menu {
                    Button(action: openDirectOCRCamera) {
                        Label("相机", systemImage: "camera")
                    }
                    Button(action: openDirectOCRPhotoPicker) {
                        Label("照片", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label("OCR 导入", systemImage: "doc.text.viewfinder")
                        .labelStyle(.iconOnly)
                }
                .disabled(morphSession.isActive)
                .accessibilityIdentifier("together.bottom-toolbar.ocr")
                .accessibilityHint("拍摄或选择纸面笔记生成草稿")
            }
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                if isMorphBackgroundDeemphasized {
                    morphSession.requestDismissal()
                } else {
                    HomeInteractionFeedback.selection()
                    openContextualComposer(router: router)
                }
            } label: {
                Label(
                    isMorphBackgroundDeemphasized ? "收起任务详情" : "新建",
                    systemImage: "plus"
                )
                .labelStyle(.iconOnly)
            }
            .disabled(morphSession.isActive && isMorphBackgroundDeemphasized == false)
            .accessibilityIdentifier("together.bottom-toolbar.add")
            .accessibilityHint(
                isMorphBackgroundDeemphasized
                    ? "保存更改并收起当前任务"
                    : "在当前视图下新建一项"
            )
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
            Text(title)
                .font(.headline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected ? AppTheme.colors.title : AppTheme.colors.textTertiary
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
        router.pendingComposerTitle = nil
        switch displayedRootSurface {
        case .today, .projects:
            beginMorphCreation(domain: .todo)
        case .routines:
            beginMorphCreation(domain: .periodic)
        }
    }

    private func beginMorphCreation(
        domain: TaskMorphDomain,
        title: String? = nil
    ) {
        guard morphSession.isActive == false else { return }
        switch domain {
        case .todo:
            appContext.homeViewModel.beginTaskCreation()
            if let title, title.isEmpty == false {
                appContext.homeViewModel.updateTaskCreationDraft { $0.title = title }
            }
            guard let session = appContext.homeViewModel.taskCreationSession else { return }
            let dayStart = Calendar.current.startOfDay(for: appContext.homeViewModel.selectedDate)
            let section = TaskMorphSection.todo(dayStart: dayStart, isUnscheduled: false)
            _ = morphSession.beginCreation(
                domain: .todo,
                id: session.id,
                placement: TaskMorphPlacement(
                    provisionalSection: section,
                    index: 0,
                    presentationID: "todo-draft-\(session.id.uuidString)"
                )
            )
        case .periodic:
            appContext.routinesViewModel.beginMorphCreation(
                defaultCycle: appContext.router.pendingPeriodicCycle ?? appContext.routinesViewModel.selectedCycle
            )
            if let title, title.isEmpty == false {
                appContext.routinesViewModel.updateCreationDraft { $0.title = title }
            }
            guard let session = appContext.routinesViewModel.creationSession else { return }
            let cycle = appContext.routinesViewModel.selectedCycle
            let section = TaskMorphSection.periodic(cycle: cycle)
            _ = morphSession.beginCreation(
                domain: .periodic,
                id: session.id,
                placement: TaskMorphPlacement(
                    provisionalSection: section,
                    index: 0,
                    presentationID: "periodic-draft-\(session.id.uuidString)"
                )
            )
        }
    }

    private func synchronizeComposerPresentation(router: AppRouter) {
        guard let route = router.activeComposer else { return }
        guard morphSession.isActive == false else {
            morphSession.requestDismissal()
            return
        }
        let title = router.pendingComposerTitle
        router.activeComposer = nil
        router.pendingComposerTitle = nil
        switch route {
        case .newTask:
            beginMorphCreation(domain: .todo, title: title)
        case .newPeriodicTask:
            beginMorphCreation(domain: .periodic, title: title)
        case .newProject:
            break
        }
    }

    private func configureMorphCallbacks() {
        morphSession.onDismissIntent = { subject in
            dismissMorph(subject)
        }
        morphSession.onCommitIntent = { subject in
            commitMorphCreation(subject)
        }
        morphSession.onCompletionIntent = { subject in
            saveAndCollapseMorph(subject, completesTask: true)
        }
        morphSession.onCreationRevealCompletionIntent = { subject, token in
            finalizeCreationReveal(subject, token: token)
        }
        morphSession.onDetailCollapseCompletionIntent = { subject, token in
            finalizeDetailCollapse(subject, token: token)
        }
    }

    private func dismissMorph(_ subject: TaskMorphSubject) {
        if subject.isDraft {
            discardMorphCreation(subject)
        } else {
            saveAndCollapseMorph(subject, completesTask: false)
        }
    }

    private func commitMorphCreation(_ subject: TaskMorphSubject) {
        guard subject.isDraft, let token = morphSession.beginSaving() else { return }
        Task { @MainActor in
            let result: TaskMorphPersistenceResult = switch subject.domain {
            case .todo:
                await appContext.homeViewModel.commitTaskCreationForMorph()
            case .periodic:
                await appContext.routinesViewModel.commitMorphCreation()
            }
            await handleCreationSaveResult(result, subject: subject, token: token)
        }
    }

    private func handleCreationSaveResult(
        _ result: TaskMorphPersistenceResult,
        subject: TaskMorphSubject,
        token: HomeMorphSessionToken
    ) async {
        switch result {
        case .failed(let message):
            morphSession.failSaving(using: token, message: message)
        case .saved(let finalPlacement):
            let persisted = TaskMorphSubject.persisted(domain: subject.domain, id: subject.id)
            var collapseToken: HomeMorphSessionToken?
            withAnimation(
                creationExitAnimation,
                completionCriteria: .logicallyComplete
            ) {
                collapseToken = morphSession.beginCollapseAfterSave(
                    using: token,
                    persistedSubject: persisted,
                    finalPlacement: finalPlacement
                )
            } completion: {
                guard let collapseToken else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    guard morphSession.beginRelocating(using: collapseToken) != nil else { return }
                    prepareCreationLanding(subject)
                }
            }
        }
    }

    private func discardMorphCreation(_ subject: TaskMorphSubject) {
        var collapseToken: HomeMorphSessionToken?
        withAnimation(
            creationExitAnimation,
            completionCriteria: .logicallyComplete
        ) {
            collapseToken = morphSession.beginDiscardCollapse()
        } completion: {
            guard let collapseToken else { return }
            switch subject.domain {
            case .todo:
                appContext.homeViewModel.discardTaskCreation()
            case .periodic:
                appContext.routinesViewModel.discardMorphCreation()
            }
            morphSession.finishDiscard(using: collapseToken)
        }
    }

    private func saveAndCollapseMorph(_ subject: TaskMorphSubject, completesTask: Bool) {
        guard subject.isDraft == false, let token = morphSession.beginSaving() else { return }
        Task { @MainActor in
            let result: TaskMorphPersistenceResult
            switch (subject.domain, completesTask) {
            case (.todo, false):
                result = await appContext.homeViewModel.saveDetailForMorph()
            case (.todo, true):
                result = await appContext.homeViewModel.completeDetailForMorph()
            case (.periodic, false):
                result = await appContext.routinesViewModel.saveDetailForMorph()
            case (.periodic, true):
                result = await appContext.routinesViewModel.completeDetailForMorph()
            }
            switch result {
            case .failed(let message):
                morphSession.failSaving(using: token, message: message)
            case .saved(let placement):
                if morphSession.detailPresentationIntent == .expanded {
                    _ = morphSession.finishSavingKeepingDetail(
                        using: token,
                        finalPlacement: placement
                    )
                    return
                }
                var collapseToken: HomeMorphSessionToken?
                withAnimation(detailCollapseAnimation) {
                    collapseToken = morphSession.beginDetailCollapseAfterSave(
                        using: token,
                        finalPlacement: placement
                    )
                }
                guard let collapseToken else { return }
                scheduleDetailCollapseCompletion(subject, token: collapseToken)
            }
        }
    }

    private func scheduleDetailCollapseCompletion(
        _ subject: TaskMorphSubject,
        token: HomeMorphSessionToken
    ) {
        detailCollapseCompletionTask?.cancel()
        let delay = Duration.seconds(
            reduceMotion
                ? TaskExpansionMotionTiming.reducedMotionDuration
                : TaskExpansionMotionTiming.collapseDuration
        )
        detailCollapseCompletionTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false,
                  morphSession.isCurrent(token),
                  morphSession.phase == .collapsing,
                  morphSession.visualState == .compact
            else { return }
            morphSession.requestDetailCollapseCompletion(subject, using: token)
        }
    }

    private func finalizeDetailCollapse(
        _ subject: TaskMorphSubject,
        token: HomeMorphSessionToken
    ) {
        guard morphSession.phase == .collapsing,
              morphSession.isCurrent(token),
              morphSession.subject == subject
        else { return }

        guard morphSession.detailRequiresRelocation else {
            finishDetailWithoutRelocation(subject, collapse: token)
            return
        }

        guard let relocation = morphSession.beginRelocating(using: token) else { return }
        relocateAndClearDetail(subject)
        Task { @MainActor in
            await Task.yield()
            guard morphSession.isCurrent(relocation) else { return }
            withAnimation(relocationAnimation) {
                morphSession.finishRelocating(using: relocation)
            }
        }
    }

    private func finishDetailWithoutRelocation(
        _ subject: TaskMorphSubject,
        collapse: HomeMorphSessionToken
    ) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            switch subject.domain {
            case .todo:
                appContext.homeViewModel.dismissItemDetail()
            case .periodic:
                appContext.routinesViewModel.finishMorphDetail()
            }
            morphSession.finishCollapse(using: collapse)
        }
    }

    private func prepareCreationLanding(_ subject: TaskMorphSubject) {
        switch subject.domain {
        case .todo:
            appContext.homeViewModel.relocateMorphItem(subject.id)
        case .periodic:
            appContext.routinesViewModel.relocateMorphTask(subject.id)
        }
    }

    private func finalizeCreationReveal(
        _ subject: TaskMorphSubject,
        token: HomeMorphSessionToken
    ) {
        guard morphSession.isCurrent(token),
              morphSession.phase == .relocating,
              morphSession.subject == subject
        else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            switch subject.domain {
            case .todo:
                appContext.homeViewModel.finalizeCommittedTaskCreation()
            case .periodic:
                appContext.routinesViewModel.finalizeMorphCreation()
            }
            morphSession.finishRelocating(using: token)
        }
    }

    private func relocateAndClearDetail(_ subject: TaskMorphSubject) {
        switch subject.domain {
        case .todo:
            appContext.homeViewModel.relocateMorphItem(subject.id)
            appContext.homeViewModel.dismissItemDetail()
        case .periodic:
            appContext.routinesViewModel.relocateMorphTask(subject.id)
            appContext.routinesViewModel.finishMorphDetail()
        }
    }

    private var morphAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.14)
            : .smooth(duration: 0.35, extraBounce: 0)
    }

    private var relocationAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.28, extraBounce: 0)
    }

    private var detailCollapseAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: TaskExpansionMotionTiming.reducedMotionDuration)
            : .smooth(duration: TaskExpansionMotionTiming.collapseDuration, extraBounce: 0)
    }

    private var creationExitAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22, extraBounce: 0)
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
        guard morphSession.isActive == false else { return }
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }
        guard surface == .today || surface == .routines else { return }
        guard router.currentSurface != surface else { return }

        HomeInteractionFeedback.selection()

        withAnimation(rootModeAnimation) {
            router.currentSurface = surface
        }
    }

    private func synchronizePendingRootRoutes(router: AppRouter) {
        guard morphSession.isActive == false else { return }
        if router.isProfilePresented, rootNavigationPath.count == 0 {
            rootNavigationPath.append(AppRootRoute.profile)
        }
        synchronizeComposerPresentation(router: router)
    }

    private func schedulePendingRootRoutes(router: AppRouter) {
        Task { @MainActor in
            await Task.yield()
            synchronizePendingRootRoutes(router: router)
        }
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
            : .smooth(duration: 0.18, extraBounce: 0.14)
    }
}
