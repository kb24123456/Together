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
        HomeRootContent(morphSession: morphSession)
            .environment(appContext)
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
    @State private var pendingCreationDomain: TaskMorphDomain?
    @State private var appIntentHandoffCenter = AppIntentHandoffCenter.shared

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
        .onChange(of: router.composerRequestRevision) { _, _ in
            synchronizeComposerPresentation(router: router)
        }
        .onChange(of: appIntentHandoffCenter.taskCreationRequestRevision) { _, _ in
            acceptNextSystemTaskCreationIfPossible(router: router)
        }
        .onChange(of: appContext.sessionStore.isAppLocked) { _, isLocked in
            guard isLocked == false else { return }
            acceptNextSystemTaskCreationIfPossible(router: router)
        }
        .onChange(of: morphSession.phase) { _, phase in
            switch phase {
            case .active, .saving, .collapsing, .relocating:
                if frozenRootSurface == nil {
                    frozenRootSurface = router.currentSurface
                }
            case .idle:
                frozenRootSurface = nil
                if let pendingCreationDomain {
                    self.pendingCreationDomain = nil
                    beginMorphCreation(domain: pendingCreationDomain)
                    return
                }
                synchronizePendingRootRoutes(router: router)
                acceptNextSystemTaskCreationIfPossible(router: router)
            }
        }
        .onAppear {
            configureMorphCallbacks()
            synchronizeComposerPresentation(router: router)
            acceptNextSystemTaskCreationIfPossible(router: router)
        }
        .onDisappear {
            detailCollapseCompletionTask?.cancel()
            morphSession.onDismissIntent = nil
            morphSession.onCreationCancelIntent = nil
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
                actsAsDismissTarget: true,
                onDismiss: morphSession.requestDismissal
            )
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if morphSession.isActive {
                    morphSession.requestDismissal()
                    return
                }
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
                actsAsDismissTarget: true,
                onDismiss: morphSession.requestDismissal
            )
        }
    }

    @ToolbarContentBuilder
    private func bottomToolbar(router: AppRouter) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            if isMorphBackgroundDeemphasized {
                Button(action: morphSession.requestDismissal) {
                    Label(
                        morphSession.isCreationFlow ? "收起键盘" : "收起任务详情",
                        systemImage: "doc.text.viewfinder"
                    )
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("together.bottom-toolbar.ocr")
                .accessibilityHint(
                    morphSession.isCreationFlow
                        ? "保留当前草稿并结束输入"
                        : "保存更改并收起当前任务"
                )
            } else {
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
                .disabled(morphSession.isActive)
                .accessibilityIdentifier("together.bottom-toolbar.ocr")
                .accessibilityHint("拍摄、选择照片或粘贴多行文字生成草稿")
            }
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
            .accessibilityIdentifier("together.bottom-toolbar.add")
            .accessibilityHint(
                morphSession.isActive
                    ? (morphSession.isCreationFlow
                        ? "请先添加或取消当前草稿"
                        : "保存并收起当前任务后新建一项")
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
        if morphSession.isActive {
            if morphSession.isCreationFlow {
                morphSession.requestCreationKeyboardDismissal()
                return
            }
            pendingCreationDomain = domain
            morphSession.requestDismissal()
            return
        }
        switch domain {
        case .todo:
            appContext.homeViewModel.beginTaskCreation()
            if let title, title.isEmpty == false {
                appContext.homeViewModel.updateTaskCreationDraft { $0.title = title }
            }
            guard let session = appContext.homeViewModel.taskCreationSession,
                  let placement = appContext.homeViewModel.taskCreationPlacement()
            else { return }
            _ = morphSession.beginCreation(
                domain: .todo,
                id: session.id,
                placement: placement
            )
        case .periodic:
            appContext.routinesViewModel.beginMorphCreation(
                defaultCycle: appContext.router.pendingPeriodicCycle ?? appContext.routinesViewModel.selectedCycle
            )
            if let title, title.isEmpty == false {
                appContext.routinesViewModel.updateCreationDraft { $0.title = title }
            }
            guard let session = appContext.routinesViewModel.creationSession,
                  let placement = appContext.routinesViewModel.creationPlacement()
            else { return }
            _ = morphSession.beginCreation(
                domain: .periodic,
                id: session.id,
                placement: placement
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
        router.clearComposerRequest()
        switch route {
        case .newTask:
            beginMorphCreation(domain: .todo, title: title)
        case .newPeriodicTask:
            beginMorphCreation(domain: .periodic, title: title)
        case .newProject:
            break
        }
        acceptNextSystemTaskCreationIfPossible(router: router)
    }

    private func acceptNextSystemTaskCreationIfPossible(router: AppRouter) {
        guard appContext.sessionStore.isAppLocked == false,
              router.activeComposer == nil,
              let request = appIntentHandoffCenter.consumeNextTaskCreation()
        else { return }

        appContext.requestTaskCreation(title: request.title)
    }

    private func configureMorphCallbacks() {
        morphSession.onDismissIntent = { subject in
            dismissMorph(subject)
        }
        morphSession.onCreationCancelIntent = { subject in
            pendingCreationDomain = nil
            discardMorphCreation(subject)
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
            morphSession.requestCreationKeyboardDismissal()
        } else {
            saveAndCollapseMorph(subject, completesTask: false)
        }
    }

    private func commitMorphCreation(_ subject: TaskMorphSubject) {
        let isTitleEmpty = switch subject.domain {
        case .todo:
            appContext.homeViewModel.isTaskCreationTitleEmpty
        case .periodic:
            appContext.routinesViewModel.isCreationTitleEmpty
        }
        guard isTitleEmpty == false else {
            morphSession.showCreationValidationError("请输入任务标题")
            return
        }
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
            guard morphSession.acknowledgeCreationSave(using: token) else { return }
            try? await Task.sleep(
                for: .seconds(TaskCreationInputTiming.saveAcknowledgementDuration)
            )
            guard Task.isCancelled == false,
                  morphSession.isCurrent(token),
                  morphSession.phase == .saving
            else { return }
            HomeInteractionFeedback.completion()
            let persisted = TaskMorphSubject.persisted(domain: subject.domain, id: subject.id)
            var collapseToken: HomeMorphSessionToken?
            withAnimation(detailCollapseAnimation) {
                collapseToken = morphSession.beginCollapseAfterSave(
                    using: token,
                    persistedSubject: persisted,
                    finalPlacement: finalPlacement
                )
            }
            guard let collapseToken else { return }
            scheduleCreationCollapseCompletion(subject, token: collapseToken, wasCommitted: true)
        }
    }

    private func discardMorphCreation(_ subject: TaskMorphSubject) {
        var collapseToken: HomeMorphSessionToken?
        withAnimation(detailCollapseAnimation) {
            collapseToken = morphSession.beginDiscardCollapse()
        }
        guard let collapseToken else { return }
        scheduleCreationCollapseCompletion(subject, token: collapseToken, wasCommitted: false)
    }

    private func scheduleCreationCollapseCompletion(
        _ subject: TaskMorphSubject,
        token: HomeMorphSessionToken,
        wasCommitted: Bool
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
            finalizeCreationCollapse(subject, token: token, wasCommitted: wasCommitted)
        }
    }

    private func finalizeCreationCollapse(
        _ subject: TaskMorphSubject,
        token: HomeMorphSessionToken,
        wasCommitted: Bool
    ) {
        guard wasCommitted else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch subject.domain {
                case .todo:
                    appContext.homeViewModel.discardTaskCreation()
                case .periodic:
                    appContext.routinesViewModel.discardMorphCreation()
                }
                morphSession.finishDiscard(using: token)
            }
            return
        }

        guard morphSession.creationRequiresRelocation else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                finalizeCommittedCreation(subject)
                morphSession.finishCollapse(using: token)
            }
            return
        }

        guard morphSession.beginRelocating(using: token) != nil else { return }
        prepareCreationLanding(subject)
    }

    private func finalizeCommittedCreation(_ subject: TaskMorphSubject) {
        switch subject.domain {
        case .todo:
            appContext.homeViewModel.finalizeCommittedTaskCreation()
        case .periodic:
            appContext.routinesViewModel.finalizeMorphCreation()
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
        if morphSession.isActive {
            morphSession.requestDismissal()
            return
        }
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
