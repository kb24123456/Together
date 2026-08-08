import PhotosUI
import SwiftUI

private enum AppRootRoute: Hashable {
    case profile
    case completedHistory(CompletedHistoryFilter)
}

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @State private var focusModel = HomeFocusPresentationModel()

    var body: some View {
        HomeRootContainer(
            rootView: HomeRootContent(focusModel: focusModel)
                .environment(appContext),
            focusView: AnyView(
                HomeFocusSurfaceView(focusModel: focusModel)
                    .environment(appContext)
                    .id(focusModel.surfaceRevision)
            ),
            focusModel: focusModel
        )
        .ignoresSafeArea()
        .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
    }
}

struct HomeRootContent: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var focusModel: HomeFocusPresentationModel
    @State private var rootNavigationPath = NavigationPath()
    @State private var activeOCRSourceSession: OCRSourceSheetSession?
    @State private var pendingOCRReviewSession: OCRReviewSession?
    @State private var isPresentingDirectOCRPhotoPicker = false
    @State private var directOCRPhotoPickerSelection: [PhotosPickerItem] = []
    @State private var directOCRProcessingTask: Task<Void, Never>?
    @State private var isPresentingDirectOCRCamera = false
    @State private var frozenRootSurface: RootSurface?

    private var displayedRootSurface: RootSurface {
        frozenRootSurface ?? appContext.router.currentSurface
    }

    var body: some View {
        @Bindable var router = appContext.router

        NavigationStack(path: $rootNavigationPath) {
                rootSurfaceView(router: router)
                    .toolbar {
                        topToolbar(router: router)
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
            .background(Color.clear)
            .allowsHitTesting(focusModel.isActive == false)
            .accessibilityHidden(focusModel.isActive)
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
            guard focusModel.isActive == false else {
                focusModel.requestDismissal()
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
        .onChange(of: focusModel.phase) { _, phase in
            switch phase {
            case .preparing, .transitioningIn, .focused, .saving, .transitioningOut, .recovering:
                if frozenRootSurface == nil {
                    frozenRootSurface = router.currentSurface
                }
            case .preparingLanding, .landing:
                break
            case .idle:
                frozenRootSurface = nil
                synchronizePendingRootRoutes(router: router)
            }
        }
        .onAppear {
            configureFocusCallbacks()
            synchronizeComposerPresentation(router: router)
        }
        .onDisappear {
            focusModel.onDismissIntent = nil
            focusModel.onDismissCompleted = nil
            focusModel.onLandingCompleted = nil
            focusModel.onRecoveryCompleted = nil
            focusModel.onCompletionIntent = nil
        }
        .task {
            StartupTrace.mark("AppRootView.visible")
        }
    }

    @ViewBuilder
    private func rootSurfaceView(router: AppRouter) -> some View {
        HomeView(
            viewModel: appContext.homeViewModel,
            focusModel: focusModel,
            projectsViewModel: appContext.projectsViewModel,
            routinesViewModel: appContext.routinesViewModel,
            isProjectModePresented: false,
            isRoutinesModePresented: displayedRootSurface == .routines,
            onCreateTaskTapped: {
                router.pendingComposerTitle = nil
                beginFocusCreation(domain: .todo)
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
                    .frame(width: 144)
                    .accessibilityIdentifier("together.mode-picker")
                    .accessibilityValue(isRoutinesModeActive ? "定期任务" : "待办任务")
                    .accessibilityHint("在待办任务和定期任务之间切换")
                }
            } else {
                Text("待办")
                    .font(.headline)
                    .foregroundStyle(AppTheme.colors.title)
                    .accessibilityAddTraits(.isHeader)
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
                    size: 32,
                    fillColor: AppTheme.colors.avatarWarm,
                    symbolColor: AppTheme.colors.title.opacity(0.82),
                    symbolFont: AppTheme.typography.sized(16, weight: .semibold),
                    overrideImage: avatar.overrideImage
                )
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("打开个人页")
            .accessibilityHint("查看个人资料和设置")
        }
    }

    private func homeBottomDock(router: AppRouter) -> some View {
        let isAvailable = appContext.homeViewModel.isDockHidden == false

        return HomeBottomDock(
            showsAuxiliaryVisual: isAvailable,
            showsAddButtonVisual: isAvailable,
            isInteractive: isAvailable && focusModel.isActive == false,
            onCamera: openDirectOCRCamera,
            onPhotos: openDirectOCRPhotoPicker,
            onAdd: {
                HomeInteractionFeedback.selection()
                openContextualComposer(router: router)
            },
            onAddFrameChanged: { _ in }
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
            beginFocusCreation(domain: .todo)
        case .routines:
            beginFocusCreation(domain: .periodic)
        }
    }

    private func beginFocusCreation(domain: HomeFocusDomain, title: String? = nil) {
        guard focusModel.isActive == false else { return }
        switch domain {
        case .todo:
            appContext.homeViewModel.beginTaskCreation()
            if let title, title.isEmpty == false {
                appContext.homeViewModel.updateTaskCreationDraft { $0.title = title }
            }
            guard let session = appContext.homeViewModel.taskCreationSession else { return }
            _ = focusModel.presentCreation(
                domain: .todo,
                sessionID: session.id,
                proposedSize: CGSize(width: 900, height: 360)
            )
        case .periodic:
            appContext.routinesViewModel.beginFocusCreation(
                defaultCycle: appContext.router.pendingPeriodicCycle ?? appContext.routinesViewModel.selectedCycle
            )
            if let title, title.isEmpty == false {
                appContext.routinesViewModel.updateCreationDraft { $0.title = title }
            }
            guard let session = appContext.routinesViewModel.creationSession else { return }
            _ = focusModel.presentCreation(
                domain: .periodic,
                sessionID: session.id,
                proposedSize: CGSize(width: 900, height: 320)
            )
        }
    }

    private func synchronizeComposerPresentation(router: AppRouter) {
        guard let route = router.activeComposer else { return }
        guard focusModel.isActive == false else {
            focusModel.requestDismissal()
            return
        }
        let title = router.pendingComposerTitle
        router.activeComposer = nil
        router.pendingComposerTitle = nil
        switch route {
        case .newTask:
            beginFocusCreation(domain: .todo, title: title)
        case .newPeriodicTask:
            beginFocusCreation(domain: .periodic, title: title)
        case .newProject:
            break
        }
    }

    private func configureFocusCallbacks() {
        focusModel.onDismissIntent = { subject in
            switch subject {
            case .creation:
                focusModel.dismissToSource()
            case .detail(.todo, _):
                guard appContext.homeViewModel.hasUnsavedDetailChanges else {
                    focusModel.dismissToSource()
                    return
                }
                saveFocusedDetail(subject)
            case .detail(.periodic, let itemID):
                guard let task = appContext.routinesViewModel.tasks.first(where: { $0.id == itemID }),
                      appContext.routinesViewModel.hasUnsavedInlineChanges(for: task)
                else {
                    focusModel.dismissToSource()
                    return
                }
                saveFocusedDetail(subject)
            }
        }

        focusModel.onDismissCompleted = { subject in
            clearFocusDomainState(for: subject)
            schedulePendingRootRoutes(router: appContext.router)
        }

        focusModel.onLandingCompleted = { subject in
            clearFocusDomainState(for: subject)
            schedulePendingRootRoutes(router: appContext.router)
        }

        focusModel.onRecoveryCompleted = { subject in
            switch subject {
            case .detail(.todo, _):
                appContext.homeViewModel.dismissItemDetail()
            case .detail(.periodic, _):
                appContext.routinesViewModel.finishFocusDetail()
            case .creation:
                break
            }
            schedulePendingRootRoutes(router: appContext.router)
        }

        focusModel.onCompletionIntent = { subject in
            guard let token = focusModel.beginSaving() else { return }
            Task { @MainActor in
                let result: HomeFocusPersistenceResult
                switch subject {
                case .detail(.todo, _):
                    result = await appContext.homeViewModel.completeDetailForFocus()
                case .detail(.periodic, _):
                    result = await appContext.routinesViewModel.completeDetailForFocus()
                case .creation:
                    return
                }
                focusModel.finishSaving(using: token, result: result)
            }
        }
    }

    private func saveFocusedDetail(_ subject: HomeFocusSubject) {
        guard let token = focusModel.beginSaving() else { return }
        Task { @MainActor in
            let result: HomeFocusPersistenceResult
            switch subject {
            case .detail(.todo, _):
                result = await appContext.homeViewModel.saveDetailForFocus()
            case .detail(.periodic, _):
                result = await appContext.routinesViewModel.saveDetailForFocus()
                if case .saved(let descriptor) = result,
                   case .periodic(let cycle) = descriptor.section {
                    appContext.routinesViewModel.selectCycle(cycle)
                }
            case .creation:
                return
            }
            focusModel.finishSaving(using: token, result: result)
        }
    }

    private func clearFocusDomainState(for subject: HomeFocusSubject) {
        switch subject {
        case .detail(.todo, _):
            appContext.homeViewModel.dismissItemDetail()
        case .creation(.todo, _):
            if appContext.homeViewModel.taskCreationSession?.phase == .committed {
                appContext.homeViewModel.finalizeCommittedTaskCreation()
            } else {
                appContext.homeViewModel.discardTaskCreation()
            }
        case .detail(.periodic, _):
            appContext.routinesViewModel.finishFocusDetail()
        case .creation(.periodic, _):
            if appContext.routinesViewModel.creationSession?.phase == .committed {
                appContext.routinesViewModel.finalizeFocusCreation()
            } else {
                appContext.routinesViewModel.discardFocusCreation()
            }
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
        guard focusModel.isActive == false else { return }
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
        guard focusModel.isActive == false else { return }
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
