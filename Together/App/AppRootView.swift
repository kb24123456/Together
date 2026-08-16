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
    @State private var dockAddFrame: CGRect?

    private var displayedRootSurface: RootSurface {
        frozenRootSurface ?? appContext.router.currentSurface
    }

    private var isMorphBackgroundDeemphasized: Bool {
        morphSession.isFocusDepthActive
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if rootNavigationPath.isEmpty {
                    homeBottomDock(router: router)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
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
            case .heroEntering, .active, .saving, .collapsing, .relocating:
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
            morphSession.onDismissIntent = nil
            morphSession.onCommitIntent = nil
            morphSession.onCompletionIntent = nil
            morphSession.onCreationRevealCompletionIntent = nil
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
            onCreateTaskTapped: {
                router.pendingComposerTitle = nil
                beginMorphCreation(domain: .todo, heroSourceFrame: nil)
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

    // MARK: - Navigation toolbar and app-owned bottom dock

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
                        Picker("任务模式", selection: rootModeSelection(router: router)) {
                            Text("待办").tag(RootSurface.today)
                            Text("定期").tag(RootSurface.routines)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 144, height: 38)
                        .frame(height: 44)
                        .accessibilityIdentifier("together.mode-picker")
                        .accessibilityValue(isRoutinesModeActive ? "定期任务" : "待办任务")
                        .accessibilityHint("切换待办或定期任务")
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
                actsAsDismissTarget: false,
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
                actsAsDismissTarget: false,
                onDismiss: morphSession.requestDismissal
            )
        }
    }

    private func homeBottomDock(router: AppRouter) -> some View {
        let isAvailable = appContext.homeViewModel.isDockHidden == false

        return HomeBottomDock(
            showsAuxiliaryVisual: isAvailable,
            showsAddButtonVisual: isAvailable && morphSession.isCreationOverlayVisible == false,
            isInteractive: isAvailable && morphSession.isActive == false,
            onCamera: openDirectOCRCamera,
            onPhotos: openDirectOCRPhotoPicker,
            onAdd: {
                HomeInteractionFeedback.selection()
                openContextualComposer(router: router)
            },
            onAddFrameChanged: { dockAddFrame = $0 }
        )
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
            beginMorphCreation(domain: .todo, heroSourceFrame: reduceMotion ? nil : dockAddFrame)
        case .routines:
            beginMorphCreation(domain: .periodic, heroSourceFrame: reduceMotion ? nil : dockAddFrame)
        }
    }

    private func beginMorphCreation(
        domain: TaskMorphDomain,
        title: String? = nil,
        heroSourceFrame: CGRect? = nil
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
                ),
                heroSourceFrame: heroSourceFrame
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
                ),
                heroSourceFrame: heroSourceFrame
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
                creationDissolveAnimation,
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
            morphAnimation,
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
                let requiresRelocation = morphSession.placement?.requiresRelocation(to: placement) ?? true
                let collapse = withAnimation(morphAnimation) {
                    morphSession.beginDetailCollapseAfterSave(using: token, finalPlacement: placement)
                }
                guard let collapse else { return }
                await waitForCollapse()
                guard morphSession.phase == .collapsing,
                      morphSession.isCurrent(collapse)
                else { return }
                guard requiresRelocation else {
                    finishDetailWithoutRelocation(subject, collapse: collapse)
                    return
                }
                let relocation = withAnimation(relocationAnimation) {
                    morphSession.beginRelocating(using: collapse)
                }
                guard let relocation else { return }
                relocateAndClearDetail(subject)
                await Task.yield()
                withAnimation(relocationAnimation) {
                    morphSession.finishRelocating(using: relocation)
                }
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
        TaskMorphBloomMotion.geometryAnimation(reduceMotion: reduceMotion)
    }

    private var relocationAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.28, extraBounce: 0)
    }

    private var creationDissolveAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22, extraBounce: 0)
    }

    private func waitForCollapse() async {
        guard reduceMotion == false else { return }
        try? await Task.sleep(for: .milliseconds(430))
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
