import PhotosUI
import SwiftUI

private enum AppRootRoute: Hashable {
    case profile
    case completedHistory(CompletedHistoryFilter)
}

private struct RootTitleBlurTransitionModifier: ViewModifier {
    let blurRadius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
    }
}

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rootNavigationPath = NavigationPath()
    @State private var activeOCRSourceSession: OCRSourceSheetSession?
    @State private var pendingOCRReviewSession: OCRReviewSession?
    @State private var isPresentingDirectOCRPhotoPicker = false
    @State private var directOCRPhotoPickerSelection: [PhotosPickerItem] = []
    @State private var directOCRProcessingTask: Task<Void, Never>?
    @State private var isPresentingDirectOCRCamera = false

    var body: some View {
        @Bindable var router = appContext.router

        NavigationStack(path: $rootNavigationPath) {
            rootSurfaceView(router: router)
                .toolbar {
                    topToolbar(router: router)
                    dockToolbar(router: router)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                .toolbarVisibility(appContext.homeViewModel.isDockHidden ? .hidden : .visible, for: .bottomBar)
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
        .background(GradientGridBackground())
        .sheet(item: $router.activeComposer, onDismiss: {
            router.pendingComposerTitle = nil
            router.pendingPeriodicCycle = nil
        }) { route in
            ComposerPlaceholderSheet(
                route: route,
                appContext: appContext,
                initialTitle: router.pendingComposerTitle,
                initialPeriodicCycle: router.pendingPeriodicCycle
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(40)
            .presentationBackground(AppTheme.colors.surface)
            .presentationBackgroundInteraction(.enabled)
            .presentationContentInteraction(.scrolls)
            .interactiveDismissDisabled(false)
            .modifier(ComposerPresentationSizingModifier())
        }
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
        .task {
            StartupTrace.mark("AppRootView.visible")
        }
    }

    @ViewBuilder
    private func rootSurfaceView(router: AppRouter) -> some View {
        HomeView(
            viewModel: appContext.homeViewModel,
            projectsViewModel: appContext.projectsViewModel,
            routinesViewModel: appContext.routinesViewModel,
            isProjectModePresented: false,
            isRoutinesModePresented: router.isRoutinesModePresented,
            onCreateTaskTapped: {
                router.pendingComposerTitle = nil
                router.activeComposer = .newTask
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

    // MARK: - Native bottom toolbar

    @ToolbarContentBuilder
    private func topToolbar(router: AppRouter) -> some ToolbarContent {
        let showsRoutinesButton = appContext.sessionStore.activeMode == .single
        let isRoutinesModeActive = router.currentSurface == .routines

        if showsRoutinesButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    toggleRoutinesSurface(router: router)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(isRoutinesModeActive ? 180 : 0))
                        .scaleEffect(isRoutinesModeActive ? 1.08 : 1)
                        .animation(projectModeAnimation, value: isRoutinesModeActive)
                }
                .tint(isRoutinesModeActive ? dockSelectionTint : AppTheme.colors.title)
                .accessibilityLabel(isRoutinesModeActive ? "关闭例行事务" : "打开例行事务")
            }
        }

        ToolbarItem(placement: .principal) {
            ZStack {
                if isRoutinesModeActive {
                    Text("例行任务")
                        .transition(rootTitleTransition)
                } else {
                    Text("任务")
                        .transition(rootTitleTransition)
                }
            }
            .font(AppTheme.typography.sized(17, weight: .semibold))
            .foregroundStyle(AppTheme.colors.title)
            .animation(rootTitleAnimation, value: isRoutinesModeActive)
            .accessibilityAddTraits(.isHeader)
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

    @ToolbarContentBuilder
    private func dockToolbar(router: AppRouter) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Menu {
                Button {
                    openDirectOCRCamera()
                } label: {
                    Label("相机", systemImage: "camera")
                }

                Button {
                    openDirectOCRPhotoPicker()
                } label: {
                    Label("照片", systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: "doc.text.viewfinder")
            }
            .buttonBorderShape(.circle)
            .accessibilityIdentifier("together.toolbar.ocr")
            .accessibilityLabel("OCR 导入")
            .accessibilityHint("拍摄或选择纸面笔记生成草稿")
        }

        if router.currentSurface == .today {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    ForEach(HomeTaskFilterOption.allCases, id: \.self) { option in
                        Button {
                            Task { await appContext.homeViewModel.toggleTaskFilter(option) }
                        } label: {
                            Label(
                                option.title,
                                systemImage: appContext.homeViewModel.selectedTaskFilters.contains(option)
                                    ? "checkmark"
                                    : option.systemImage
                            )
                        }
                    }

                    if appContext.homeViewModel.isTaskFilterActive {
                        Divider()
                        Button("清除搜索和筛选", role: .destructive) {
                            appContext.homeViewModel.clearTaskFilters()
                        }
                    }
                } label: {
                    Image(
                        systemName: appContext.homeViewModel.selectedTaskFilterCount > 0
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityLabel("筛选任务")
                .accessibilityValue(
                    appContext.homeViewModel.selectedTaskFilterCount == 0
                        ? "未筛选"
                        : "已选择 \(appContext.homeViewModel.selectedTaskFilterCount) 项"
                )
            }
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                HomeInteractionFeedback.selection()
                openContextualComposer(router: router)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建")
            .accessibilityHint("在当前视图下新建一项")
        }
    }

    // MARK: - Surface routing

    private var dockSelectionTint: Color {
        .blue
    }

    private var projectModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private var rootTitleTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .modifier(
            active: RootTitleBlurTransitionModifier(
                blurRadius: 2,
                opacity: 0
            ),
            identity: RootTitleBlurTransitionModifier(
                blurRadius: 0,
                opacity: 1
            )
        )
    }

    private var rootTitleAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .smooth(duration: 0.42, extraBounce: 0)
    }

    private func returnToToday(router: AppRouter) {
        let surface = router.currentSurface
        switch surface {
        case .routines:
            toggleRoutinesSurface(router: router)
        case .projects:
            router.currentSurface = .today
        case .today:
            break
        }
    }

    private func openProfile(router: AppRouter) {
        guard router.isProfilePresented == false else { return }
        router.isProfilePresented = true
    }

    private func openContextualComposer(router: AppRouter) {
        router.pendingComposerTitle = nil
        switch router.currentSurface {
        case .today, .projects:
            router.activeComposer = .newTask
        case .routines:
            router.activeComposer = .newPeriodicTask
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

    private func toggleRoutinesSurface(router: AppRouter) {
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }

        HomeInteractionFeedback.selection()

        withAnimation(projectModeAnimation) {
            if router.currentSurface == .routines {
                router.currentSurface = .today
            } else {
                router.currentSurface = .routines
            }
        }
    }

}


private struct ComposerPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
