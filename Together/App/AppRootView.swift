import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quickCaptureInputBridge = QuickCaptureInputBridge()
    @State private var isQuickCapturePresented = false
    @State private var quickCaptureText = ""
    @State private var isSubmittingQuickCapture = false
    @State private var isQuickCaptureFocused = false
    @State private var quickCaptureDebugMessage: String?
    @State private var quickCaptureHasVisibleText = false
    @State private var lastKeyboardOverlap: CGFloat = 0
    @State private var quickCaptureFieldHeight: CGFloat = 52
    @State private var quickCaptureSpeechRecognizer = QuickCaptureSpeechRecognizer()
    @State private var pendingQuickCaptureConfirmation: QuickCapturePendingConfirmation?
    @State private var isDockHubExpanded = false
    @State private var dockHubNotice: DockHubNotice?
    @StateObject private var keyboardObserver = TaskEditorKeyboardObserver()

    private let quickCaptureTranscriptPreviewThreshold = 16
    private let quickCaptureFieldMinHeight: CGFloat = 52
    private let quickCaptureFieldMaxHeight: CGFloat = 112

    var body: some View {
        @Bindable var router = appContext.router

        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                NavigationStack {
                    rootSurfaceView(router: router)
                }
                .blur(radius: isQuickCapturePresented ? 8 : 0)
                .allowsHitTesting(!isQuickCapturePresented)
                .animation(.easeOut(duration: 0.2), value: isQuickCapturePresented)

                if isQuickCapturePresented {
                    quickCaptureBackdrop
                        .transition(.opacity)
                }

                overlayChrome(bottomInset: proxy.safeAreaInsets.bottom, router: router)
            }
            .background(
                AppTheme.colors.background.ignoresSafeArea()
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $router.isProfilePresented) {
            NavigationStack {
                ProfileView(viewModel: appContext.profileViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") {
                                router.isProfilePresented = false
                            }
                        }
                }
            }
            .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
        }
        .sheet(item: $router.activeComposer, onDismiss: {
            router.pendingComposerTitle = nil
        }) { route in
            ComposerPlaceholderSheet(
                route: route,
                appContext: appContext,
                initialTitle: router.pendingComposerTitle
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
        .sheet(item: $pendingQuickCaptureConfirmation, onDismiss: {
            if isQuickCapturePresented && !isSubmittingQuickCapture {
                isQuickCaptureFocused = true
            }
        }) { confirmation in
            quickCaptureConfirmationSheet(confirmation)
        }
        .alert(item: $dockHubNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .environment(\.symbolVariants, .none)
        .font(AppTheme.typography.body)
        .tint(AppTheme.colors.title)
        .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
        .onChange(of: quickCaptureSpeechRecognizer.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            quickCaptureText = newValue
        }
        .onChange(of: quickCaptureText) { _, newValue in
            guard newValue != quickCaptureSpeechRecognizer.transcript else { return }
            quickCaptureSpeechRecognizer.syncDraftText(newValue)
            if quickCaptureSpeechRecognizer.isListening {
                quickCaptureSpeechRecognizer.stopListening()
            }
        }
        .onChange(of: keyboardObserver.overlap) { _, newValue in
            if newValue > 0 {
                lastKeyboardOverlap = newValue
            }
        }
        .onChange(of: isQuickCapturePresented) { _, isPresented in
            if !isPresented {
                quickCaptureSpeechRecognizer.stopListening()
                quickCaptureSpeechRecognizer.clearError()
            } else {
                collapseDockHub()
                quickCaptureText = ""
                quickCaptureSpeechRecognizer.resetDraft()
            }
        }
        .onChange(of: router.currentSurface) { _, _ in
            syncDockHubPresentation(router: router)
        }
        .onChange(of: router.isProfilePresented) { _, _ in
            syncDockHubPresentation(router: router)
        }
        .onChange(of: router.activeComposer?.id) { _, _ in
            syncDockHubPresentation(router: router)
        }
        .onChange(of: pendingQuickCaptureConfirmation?.id) { _, _ in
            syncDockHubPresentation(router: router)
        }
        .alert(
            "语音输入不可用",
            isPresented: Binding(
                get: { quickCaptureSpeechRecognizer.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        quickCaptureSpeechRecognizer.clearError()
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                quickCaptureSpeechRecognizer.clearError()
            }
        } message: {
            Text(quickCaptureSpeechRecognizer.errorMessage ?? "")
        }
        .alert(
            "快速捕捉提交诊断",
            isPresented: Binding(
                get: { quickCaptureDebugMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        quickCaptureDebugMessage = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                quickCaptureDebugMessage = nil
            }
        } message: {
            Text(quickCaptureDebugMessage ?? "")
        }
        .task {
            StartupTrace.mark("AppRootView.visible")
        }
    }

    @ViewBuilder
    private func rootSurfaceView(router: AppRouter) -> some View {
        switch router.currentSurface {
        case .today, .projects, .routines:
            HomeView(
                viewModel: appContext.homeViewModel,
                projectsViewModel: appContext.projectsViewModel,
                routinesViewModel: appContext.routinesViewModel,
                isProjectModePresented: router.isProjectModePresented,
                isRoutinesModePresented: router.isRoutinesModePresented,
                onCreateTaskTapped: {
                    closeProjectsMode(router: router)
                    collapseDockHub()
                    dismissQuickCapture()
                    router.pendingComposerTitle = nil
                    router.activeComposer = .newTask
                }
            )
        case .calendar:
            CalendarView(
                viewModel: appContext.calendarViewModel,
                showsNavigationChrome: false
            )
        }
    }

    @ViewBuilder
    private func overlayChrome(bottomInset: CGFloat, router: AppRouter) -> some View {
        let dockPeripheralInset = max(8, bottomInset - 26)
        let pinnedKeyboardOverlap =
            keyboardObserver.overlap > 0
            ? keyboardObserver.overlap
            : ((quickCaptureSpeechRecognizer.state == .authorizing || quickCaptureSpeechRecognizer.isListening) ? lastKeyboardOverlap : 0)
        let captureBottom = pinnedKeyboardOverlap > 0 ? pinnedKeyboardOverlap + 8 : bottomInset + 8

        ZStack(alignment: .bottom) {
            if isDockHubExpanded && !isQuickCapturePresented {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        collapseDockHub()
                    }
                    .transition(.opacity)
            }

            if let debugMessage = quickCaptureDebugMessage, isQuickCapturePresented {
                quickCaptureDebugPanel(debugMessage)
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.bottom, captureBottom + 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            if shouldShowQuickCaptureTranscriptPreview {
                quickCaptureTranscriptPreview
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.bottom, captureBottom + 84)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
                    .zIndex(1.5)
            }

            if !isQuickCapturePresented {
                if isDockHubExpanded {
                    dockHubActionTray(bottomPadding: dockPeripheralInset + 74)
                        .transition(
                            .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .bottom))
                        )
                        .zIndex(1.7)
                }

                HomeDockBar(
                    edgeInset: dockPeripheralInset,
                    selectedDestination: router.selectedDockDestination,
                    isMonthModeActive: appContext.homeViewModel.isMonthMode,
                    isRoutinesModeActive: router.currentSurface == .routines,
                    isProjectsModeActive: router.isProjectModePresented,
                    isHubExpanded: isDockHubExpanded,
                    isInteractionEnabled: pendingQuickCaptureConfirmation == nil,
                    onProfileTapped: {
                        collapseDockHub()
                        dismissQuickCapture()
                        router.isProfilePresented = true
                    },
                    onCalendarTapped: {
                        toggleCalendarSurface(router: router)
                    },
                    onRoutinesTapped: {
                        toggleRoutinesSurface(router: router)
                    },
                    onHubPrimaryTapped: {
                        openContextualComposer(router: router)
                    },
                    onHubLongPressed: {
                        toggleDockHub()
                    },
                    onProjectsTapped: {
                        toggleProjectsSurface(router: router)
                    }
                )
                .padding(.bottom, dockPeripheralInset)
                .offset(y: appContext.homeViewModel.isDockHidden ? 120 : 0)
                .opacity(appContext.homeViewModel.isDockHidden ? 0 : 1)
                .zIndex(1.8)
            }

            if isQuickCapturePresented {
                quickCaptureBar
                    .padding(.bottom, captureBottom)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isQuickCapturePresented)
        .animation(.easeOut(duration: 0.2), value: quickCaptureDebugMessage)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: shouldShowQuickCaptureTranscriptPreview)
        .animation(projectModeAnimation, value: router.currentSurface)
        .allowsHitTesting(true)
    }

    private var projectModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private var shouldShowQuickCaptureTranscriptPreview: Bool {
        guard isQuickCapturePresented else { return false }
        guard quickCaptureSpeechRecognizer.isListening || quickCaptureSpeechRecognizer.state == .authorizing else { return false }

        let trimmed = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return trimmed.count > quickCaptureTranscriptPreviewThreshold || trimmed.contains("\n")
    }

    private var quickCaptureTranscriptPreview: some View {
        QuickCaptureTranscriptPreviewCard(
            text: quickCaptureText,
            isPreparing: quickCaptureSpeechRecognizer.state == .authorizing
        )
    }

    private func quickCaptureDebugPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                Text("快速捕捉提交诊断")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    quickCaptureDebugMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            Text(message)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.colors.body.opacity(0.84))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.colors.separator.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: AppTheme.colors.shadow.opacity(0.16), radius: 16, y: 8)
    }

    private var quickCaptureBackdrop: some View {
        ZStack {
            NativeBackdropBlur(style: .systemUltraThinMaterial)
                .opacity(0.78)
                .ignoresSafeArea()

            Color.black
                .opacity(0.02)
                .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissQuickCapture()
        }
    }

    private var quickCaptureBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.9))
                    .frame(width: 22, height: 22)

                ZStack(alignment: .leading) {
                    if quickCaptureText.isEmpty {
                        Text("快速记下一件事")
                            .font(AppTheme.typography.sized(17, weight: .regular))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.35))
                            .allowsHitTesting(false)
                    }

                    NativeQuickCaptureTextEditor(
                        bridge: quickCaptureInputBridge,
                        text: $quickCaptureText,
                        isFocused: $isQuickCaptureFocused,
                        isSubmitting: isSubmittingQuickCapture,
                        minHeight: quickCaptureFieldMinHeight,
                        maxHeight: quickCaptureFieldMaxHeight,
                        onHeightChange: { height in
                            quickCaptureFieldHeight = height
                        },
                        onContentPresenceChanged: { hasContent in
                            guard quickCaptureHasVisibleText != hasContent else { return }
                            quickCaptureHasVisibleText = hasContent
                        },
                        onSubmit: { finalText in
                            submitQuickCapture(finalText)
                        },
                        onDebug: { message in
                            quickCaptureDebugMessage = message
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if quickCaptureSpeechRecognizer.isListening || quickCaptureSpeechRecognizer.state == .authorizing {
                    VoiceActivityIndicator(
                        level: quickCaptureSpeechRecognizer.audioLevel,
                        isAuthorizing: quickCaptureSpeechRecognizer.state == .authorizing,
                        isVoiceDetected: quickCaptureSpeechRecognizer.isVoiceDetected
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Button {
                    toggleSpeechInput()
                } label: {
                    Image(systemName: quickCaptureSpeechRecognizer.isListening ? "mic.fill" : "mic")
                        .font(AppTheme.typography.sized(18, weight: .semibold))
                        .foregroundStyle(
                            quickCaptureSpeechRecognizer.isListening
                            ? AppTheme.colors.coral
                            : AppTheme.colors.body.opacity(0.9)
                        )
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(isSubmittingQuickCapture)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .frame(height: quickCaptureFieldHeight, alignment: .center)
            .modifier(QuickCaptureFieldGlassModifier())

            ZStack {
                NativeQuickCaptureSendButton(
                    bridge: quickCaptureInputBridge,
                    isEnabled: !isSubmittingQuickCapture
                )
                .frame(width: 50, height: 50)

                Image(systemName: "arrow.up")
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.9))
                    .frame(width: 50, height: 50)
                    .allowsHitTesting(false)
            }
            .modifier(QuickCaptureSendGlassModifier())
            .opacity(quickCaptureHasVisibleText ? 1 : 0.42)
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: quickCaptureFieldHeight)
    }

    private func dockHubActionTray(bottomPadding: CGFloat) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    dockHubActionTrayContent
                }
            } else {
                dockHubActionTrayContent
            }
        }
        .padding(.horizontal, AppTheme.spacing.xl)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var dockHubActionTrayContent: some View {
        VStack(spacing: 10) {
            ForEach(DockHubAction.allCases) { action in
                Button {
                    performDockHubAction(action)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.systemImage)
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(AppTheme.typography.sized(16, weight: .semibold))

                            Text(action.subtitle)
                                .font(AppTheme.typography.sized(12, weight: .medium))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.58))
                        }

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(action.isAvailable ? AppTheme.colors.body : AppTheme.colors.body.opacity(0.42))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .modifier(DockHubActionGlassModifier(isAvailable: action.isAvailable))
                .accessibilityLabel(action.title)
                .accessibilityHint(action.accessibilityHint)
            }
        }
    }

    private func performDockHubAction(_ action: DockHubAction) {
        switch action {
        case .quickCapture:
            toggleQuickCapture()
        case .newProject:
            openProjectComposer(router: appContext.router)
        case .agent:
            collapseDockHub()
            dockHubNotice = DockHubNotice(
                title: "Agent 即将到来",
                message: "这里会承接未来的 Agent 入口，本轮先保留信息架构占位。"
            )
        }
    }

    private func toggleDockHub() {
        let shouldExpand = !isDockHubExpanded
        guard shouldExpand || !DockHubPresentationState(
            isProjectModePresented: appContext.router.currentSurface != .today,
            isQuickCapturePresented: isQuickCapturePresented,
            isProfilePresented: appContext.router.isProfilePresented,
            hasActiveComposer: appContext.router.activeComposer != nil,
            hasPendingQuickCaptureConfirmation: pendingQuickCaptureConfirmation != nil
        ).shouldCollapseHub else {
            return
        }

        withAnimation(dockHubAnimation) {
            isDockHubExpanded = shouldExpand
        }
    }

    private func collapseDockHub(animated: Bool = true) {
        guard isDockHubExpanded else { return }
        if animated {
            withAnimation(dockHubAnimation) {
                isDockHubExpanded = false
            }
        } else {
            isDockHubExpanded = false
        }
    }

    private func syncDockHubPresentation(router: AppRouter) {
        let state = DockHubPresentationState(
            isProjectModePresented: router.currentSurface != .today,
            isQuickCapturePresented: isQuickCapturePresented,
            isProfilePresented: router.isProfilePresented,
            hasActiveComposer: router.activeComposer != nil,
            hasPendingQuickCaptureConfirmation: pendingQuickCaptureConfirmation != nil
        )

        if state.shouldCollapseHub {
            collapseDockHub(animated: false)
        }
    }

    private func openTaskComposer(router: AppRouter) {
        closeProjectsMode(router: router)
        collapseDockHub()
        dismissQuickCapture()
        router.pendingComposerTitle = nil
        router.activeComposer = .newTask
    }

    private func openProjectComposer(router: AppRouter) {
        closeProjectsMode(router: router)
        collapseDockHub()
        dismissQuickCapture()
        router.pendingComposerTitle = nil
        router.activeComposer = .newProject
    }

    private func openContextualComposer(router: AppRouter) {
        collapseDockHub()
        dismissQuickCapture()
        router.pendingComposerTitle = nil
        switch router.currentSurface {
        case .today, .calendar:
            router.activeComposer = .newTask
        case .projects:
            router.activeComposer = .newProject
        case .routines:
            router.activeComposer = .newPeriodicTask
        }
    }

    private var dockHubAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.16)
            : .spring(response: 0.3, dampingFraction: 0.86)
    }

    private func toggleQuickCapture() {
        appContext.router.currentSurface = .today
        collapseDockHub()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isQuickCapturePresented.toggle()
        }

        if isQuickCapturePresented {
            quickCaptureText = ""
            quickCaptureHasVisibleText = false
            quickCaptureSpeechRecognizer.resetDraft()
            Task { @MainActor in
                isQuickCaptureFocused = true
            }
        } else {
            isQuickCaptureFocused = false
        }
    }

    private func dismissQuickCapture() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isQuickCapturePresented = false
        }
        quickCaptureSpeechRecognizer.stopListening()
        quickCaptureSpeechRecognizer.resetDraft()
        isQuickCaptureFocused = false
        pendingQuickCaptureConfirmation = nil
        quickCaptureDebugMessage = nil
        quickCaptureText = ""
        quickCaptureHasVisibleText = false
        quickCaptureFieldHeight = quickCaptureFieldMinHeight
    }

    private func openProjectsMode(router: AppRouter) {
        guard !isQuickCapturePresented else { return }
        guard pendingQuickCaptureConfirmation == nil else { return }
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }
        guard router.isProjectModePresented == false else { return }

        collapseDockHub()
        HomeInteractionFeedback.selection()
        withAnimation(projectModeAnimation) {
            appContext.homeViewModel.setCalendarDisplayMode(.week)
            router.currentSurface = .projects
        }
    }

    private func closeProjectsMode(router: AppRouter) {
        guard router.isProjectModePresented else { return }

        collapseDockHub()
        HomeInteractionFeedback.selection()
        withAnimation(projectModeAnimation) {
            router.currentSurface = .today
        }
    }

    private func toggleProjectsSurface(router: AppRouter) {
        if router.currentSurface == .projects {
            closeProjectsMode(router: router)
        } else {
            openProjectsMode(router: router)
        }
    }

    private func toggleRoutinesSurface(router: AppRouter) {
        guard !isQuickCapturePresented else { return }
        guard pendingQuickCaptureConfirmation == nil else { return }
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }

        collapseDockHub()
        HomeInteractionFeedback.selection()

        withAnimation(projectModeAnimation) {
            if router.currentSurface == .routines {
                router.currentSurface = .today
            } else {
                appContext.homeViewModel.setCalendarDisplayMode(.week)
                router.currentSurface = .routines
            }
        }
    }

    private func toggleCalendarSurface(router: AppRouter) {
        guard !isQuickCapturePresented else { return }
        guard pendingQuickCaptureConfirmation == nil else { return }
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }

        collapseDockHub()
        HomeInteractionFeedback.selection()

        withAnimation(projectModeAnimation) {
            if router.currentSurface == .projects {
                router.currentSurface = .today
                appContext.homeViewModel.setCalendarDisplayMode(.month)
            } else {
                router.currentSurface = .today
                appContext.homeViewModel.toggleCalendarDisplayMode()
            }
        }
    }

    private func submitQuickCapture(_ rawTitle: String? = nil) {
        let trimmedTitle = (rawTitle ?? quickCaptureText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !isSubmittingQuickCapture else {
            quickCaptureDebugMessage = quickCaptureSubmissionSnapshot(
                reason: "提交前被拦截",
                chosenTitle: trimmedTitle
            )
            return
        }

        isSubmittingQuickCapture = true
        HomeInteractionFeedback.selection()
        isQuickCaptureFocused = false

        Task {
            let result = await appContext.homeViewModel.createQuickCaptureTask(title: trimmedTitle)
            await MainActor.run {
                isSubmittingQuickCapture = false
                switch result {
                case .saved:
                    quickCaptureDebugMessage = nil
                    quickCaptureText = ""
                    quickCaptureHasVisibleText = false
                    quickCaptureFieldHeight = quickCaptureFieldMinHeight
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        isQuickCapturePresented = false
                    }
                    quickCaptureSpeechRecognizer.stopListening()
                    quickCaptureSpeechRecognizer.resetDraft()
                    HomeInteractionFeedback.soft()
                case let .needsTimeConfirmation(confirmation):
                    quickCaptureDebugMessage = nil
                    quickCaptureText = confirmation.title
                    quickCaptureHasVisibleText = true
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        pendingQuickCaptureConfirmation = confirmation
                    }
                    isQuickCaptureFocused = false
                    quickCaptureFieldHeight = quickCaptureFieldMinHeight
                    quickCaptureSpeechRecognizer.stopListening()
                    quickCaptureSpeechRecognizer.resetDraft()
                    HomeInteractionFeedback.soft()
                case let .suggestPeriodicTask(title):
                    quickCaptureDebugMessage = nil
                    quickCaptureText = ""
                    quickCaptureHasVisibleText = false
                    quickCaptureFieldHeight = quickCaptureFieldMinHeight
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        isQuickCapturePresented = false
                    }
                    quickCaptureSpeechRecognizer.stopListening()
                    quickCaptureSpeechRecognizer.resetDraft()
                    appContext.router.pendingComposerTitle = title
                    appContext.router.activeComposer = .newPeriodicTask
                    HomeInteractionFeedback.soft()
                case .failed:
                    quickCaptureDebugMessage = quickCaptureSubmissionSnapshot(
                        reason: "createQuickCaptureTask 保存失败",
                        chosenTitle: trimmedTitle
                    )
                }
            }
        }
    }

    private func quickCaptureSubmissionSnapshot(reason: String, chosenTitle: String) -> String {
        let transcript = quickCaptureSpeechRecognizer.transcript

        return [
            "原因: \(reason)",
            "quickCaptureText: \(quickCaptureText)",
            "speechTranscript: \(transcript)",
            "chosenTitle: \(chosenTitle)"
        ].joined(separator: "\n")
    }

    private func toggleSpeechInput() {
        HomeInteractionFeedback.selection()
        if !quickCaptureSpeechRecognizer.isListening {
            quickCaptureSpeechRecognizer.beginAuthorization()
        }
        Task {
            await quickCaptureSpeechRecognizer.toggleListening(currentText: quickCaptureText)
            if quickCaptureSpeechRecognizer.isListening {
                isQuickCaptureFocused = false
            } else {
                isQuickCaptureFocused = true
            }
        }
    }

    private func dismissQuickCaptureConfirmation(restoreFocus: Bool) {
        HomeInteractionFeedback.selection()
        pendingQuickCaptureConfirmation = nil
        guard restoreFocus else { return }
        Task { @MainActor in
            isQuickCaptureFocused = true
        }
    }

    private func confirmQuickCaptureSelection(
        _ confirmation: QuickCapturePendingConfirmation,
        reminderAt: Date
    ) {
        HomeInteractionFeedback.selection()
        isSubmittingQuickCapture = true

        Task {
            let didSave = await appContext.homeViewModel.confirmQuickCaptureTask(
                confirmation,
                reminderAt: reminderAt
            )
            await MainActor.run {
                isSubmittingQuickCapture = false
                if didSave {
                    HomeInteractionFeedback.completion()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        pendingQuickCaptureConfirmation = nil
                    }
                    dismissQuickCapture()
                } else {
                    quickCaptureDebugMessage = "原因: 轻确认保存失败\nchosenTitle: \(confirmation.title)"
                }
            }
        }
    }

    @ViewBuilder
    private func quickCaptureConfirmationSheet(
        _ confirmation: QuickCapturePendingConfirmation
    ) -> some View {
        Group {
            switch confirmation.confirmationKind {
            case .timeOnly:
                QuickCaptureTimeOnlyConfirmationSheet(
                    confirmation: confirmation,
                    onConfirm: { selectedDate in
                        confirmQuickCaptureSelection(confirmation, reminderAt: selectedDate)
                    }
                )
                .interactiveDismissDisabled(isSubmittingQuickCapture)
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationDetents([.fraction(0.5)])
                .presentationCornerRadius(56)
                .modifier(QuickCaptureSheetGlassBackgroundModifier())
            case .dateAndTime:
                QuickCaptureDateTimeConfirmationSheet(
                    confirmation: confirmation,
                    isSubmitting: isSubmittingQuickCapture,
                    onCancel: {
                        dismissQuickCaptureConfirmation(restoreFocus: true)
                    },
                    onConfirm: { selectedDate in
                        confirmQuickCaptureSelection(confirmation, reminderAt: selectedDate)
                    }
                )
                .interactiveDismissDisabled(isSubmittingQuickCapture)
                .presentationDragIndicator(.hidden)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationCornerRadius(56)
                .modifier(QuickCaptureSheetGlassBackgroundModifier())
                .modifier(QuickCaptureDateTimeConfirmationPresentationSizingModifier())
            }
        }
    }
}

private struct VoiceActivityIndicator: View {
    let level: CGFloat
    let isAuthorizing: Bool
    let isVoiceDetected: Bool

    private let barBaseHeights: [CGFloat] = [5, 7.5, 11, 7.5, 5]
    private let barAmplitudeWeights: [CGFloat] = [0.16, 0.42, 1.0, 0.42, 0.16]
    private let phaseOffsets: [Double] = [0.15, 0.75, 1.25, 1.75, 2.35]

    var body: some View {
        let effectiveLevel = isAuthorizing ? 0 : level
        let showsDotState = isAuthorizing || !isVoiceDetected

        Group {
            if showsDotState {
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(AppTheme.colors.body.opacity(0.75))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let voiceStrength = min(max(effectiveLevel, 0.72), 1)

                    HStack(alignment: .center, spacing: 2.5) {
                        ForEach(Array(barBaseHeights.enumerated()), id: \.offset) { index, baseHeight in
                            let ripple = (sin((time * 8.4) + phaseOffsets[index]) + 1) * 0.5
                            let animatedWeight = 0.25 + ripple * 0.75
                            let height = baseHeight + (voiceStrength * 22 * barAmplitudeWeights[index] * animatedWeight)

                            Capsule(style: .continuous)
                                .fill(AppTheme.colors.body.opacity(0.78))
                                .frame(width: 3, height: height)
                                .offset(y: index == 2 ? 0 : 0.5)
                        }
                    }
                }
            }
        }
        .frame(width: 28, height: 24)
        .accessibilityHidden(true)
    }
}

private struct NativeBackdropBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct DockHubPresentationState: Equatable {
    let isProjectModePresented: Bool
    let isQuickCapturePresented: Bool
    let isProfilePresented: Bool
    let hasActiveComposer: Bool
    let hasPendingQuickCaptureConfirmation: Bool

    var shouldCollapseHub: Bool {
        isProjectModePresented
            || isQuickCapturePresented
            || isProfilePresented
            || hasActiveComposer
            || hasPendingQuickCaptureConfirmation
    }
}

private struct DockHubNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum DockHubAction: String, CaseIterable, Identifiable {
    case quickCapture
    case newProject
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickCapture:
            "快速捕捉"
        case .newProject:
            "新建项目"
        case .agent:
            "Agent（即将到来）"
        }
    }

    var subtitle: String {
        switch self {
        case .quickCapture:
            "快速记下一件事，稍后再整理"
        case .newProject:
            "为中周期目标建立项目容器"
        case .agent:
            "预留给后续智能执行入口"
        }
    }

    var systemImage: String {
        switch self {
        case .quickCapture:
            "square.and.pencil"
        case .newProject:
            "folder.badge.plus"
        case .agent:
            "sparkles"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .agent:
            false
        case .quickCapture, .newProject:
            true
        }
    }

    var accessibilityHint: String {
        switch self {
        case .quickCapture:
            "打开快速捕捉输入栏"
        case .newProject:
            "打开新建项目表单"
        case .agent:
            "该入口暂未开放"
        }
    }
}

private final class QuickCaptureInputBridge {
    weak var coordinator: NativeQuickCaptureTextEditor.Coordinator?

    func submit() {
        coordinator?.submitFromExternalButton()
    }
}

private struct NativeQuickCaptureTextEditor: UIViewRepresentable {
    let bridge: QuickCaptureInputBridge
    @Binding var text: String
    @Binding var isFocused: Bool
    let isSubmitting: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onContentPresenceChanged: (Bool) -> Void
    let onSubmit: (String) -> Void
    let onDebug: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            bridge: bridge,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.enablesReturnKeyAutomatically = true
        textView.returnKeyType = .send
        textView.tintColor = UIColor(AppTheme.colors.title)
        textView.font = AppTheme.typography.sizedUIFont(17, weight: .regular)
        textView.textColor = UIColor(AppTheme.colors.title)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textView = textView
        bridge.coordinator = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onDebug = onDebug
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.onContentPresenceChanged = onContentPresenceChanged
        context.coordinator.textView = textView
        bridge.coordinator = context.coordinator

        context.coordinator.applySwiftUITextUpdate(text, to: textView)
        context.coordinator.updateContentPresence(using: textView)
        context.coordinator.updateMeasuredHeight(using: textView)

        textView.isEditable = !isSubmitting
        textView.isSelectable = !isSubmitting
        textView.isUserInteractionEnabled = !isSubmitting

        let isFirstResponder = textView.isFirstResponder
        if isFocused && !isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if !isFocused && isFirstResponder {
            DispatchQueue.main.async {
                textView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        private let minHeight: CGFloat
        private let maxHeight: CGFloat
        private var isApplyingSwiftUIUpdate = false
        weak var bridge: QuickCaptureInputBridge?
        weak var textView: UITextView?
        var onSubmit: (String) -> Void = { _ in }
        var onDebug: (String) -> Void = { _ in }
        var onHeightChange: (CGFloat) -> Void = { _ in }
        var onContentPresenceChanged: (Bool) -> Void = { _ in }

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            bridge: QuickCaptureInputBridge,
            minHeight: CGFloat,
            maxHeight: CGFloat
        ) {
            _text = text
            _isFocused = isFocused
            self.bridge = bridge
            self.minHeight = minHeight
            self.maxHeight = maxHeight
        }

        func submitFromExternalButton() {
            guard let textView else {
                onDebug("原因: UITextView 不存在\nsource: sendButton")
                return
            }
            submitCurrentText(from: textView, source: "sendButton")
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingSwiftUIUpdate else { return }
            text = currentDocumentText(from: textView)
            updateContentPresence(using: textView)
            updateMeasuredHeight(using: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingSwiftUIUpdate else { return }
            let currentText = currentDocumentText(from: textView)
            if !currentText.isEmpty {
                text = currentText
            }
            updateContentPresence(using: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !isApplyingSwiftUIUpdate else { return }
            isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard !isApplyingSwiftUIUpdate else { return }
            text = currentDocumentText(from: textView)
            isFocused = false
            updateContentPresence(using: textView)
            updateMeasuredHeight(using: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
        ) -> Bool {
            guard replacementText == "\n" else { return true }
            submitCurrentText(from: textView, source: "keyboardSend")
            return false
        }

        private func submitCurrentText(from textView: UITextView, source: String) {
            let finalText = resolvedSubmissionText(from: textView).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !finalText.isEmpty else {
                onDebug([
                    "原因: UIKit 提交拿到空文本",
                    "source: \(source)",
                    "textView.text: \(textView.text ?? "")",
                    "documentText: \(currentDocumentText(from: textView))",
                    "hasMarkedText: \(textView.markedTextRange != nil ? "yes" : "no")",
                    "bindingText: \(text)"
                ].joined(separator: "\n"))
                return
            }

            self.text = finalText
            isFocused = false
            textView.resignFirstResponder()
            onSubmit(finalText)
        }

        func updateContentPresence(using textView: UITextView) {
            let hasContent = !resolvedSubmissionText(from: textView)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            DispatchQueue.main.async { [onContentPresenceChanged] in
                onContentPresenceChanged(hasContent)
            }
        }

        private func resolvedSubmissionText(from textView: UITextView) -> String {
            let documentText = currentDocumentText(from: textView)
            let plainText = textView.text ?? ""
            let bindingText = text

            let candidates = [documentText, bindingText, plainText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return candidates.max(by: { $0.count < $1.count }) ?? ""
        }

        private func currentDocumentText(from textView: UITextView) -> String {
            if let markedRange = textView.markedTextRange,
               let markedText = textView.text(in: markedRange) {
                let prefixText: String
                if let prefixRange = textView.textRange(
                    from: textView.beginningOfDocument,
                    to: markedRange.start
                ) {
                    prefixText = textView.text(in: prefixRange) ?? ""
                } else {
                    prefixText = ""
                }

                let suffixText: String
                if let suffixRange = textView.textRange(
                    from: markedRange.end,
                    to: textView.endOfDocument
                ) {
                    suffixText = textView.text(in: suffixRange) ?? ""
                } else {
                    suffixText = ""
                }

                return prefixText + markedText + suffixText
            }

            if let range = textView.textRange(from: textView.beginningOfDocument, to: textView.endOfDocument),
               let fullText = textView.text(in: range) {
                return fullText
            }

            return textView.text ?? ""
        }

        func applySwiftUITextUpdate(_ updatedText: String, to textView: UITextView) {
            guard textView.text != updatedText else { return }
            isApplyingSwiftUIUpdate = true
            textView.text = updatedText
            updateMeasuredHeight(using: textView)
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingSwiftUIUpdate = false
            }
        }

        func updateMeasuredHeight(using textView: UITextView) {
            let targetWidth = textView.bounds.width
            guard targetWidth > 1 else {
                DispatchQueue.main.async { [onHeightChange, minHeight] in
                    onHeightChange(minHeight)
                }
                return
            }
            let fittingSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            let measuredHeight = textView.sizeThatFits(fittingSize).height
            let clampedHeight = min(max(measuredHeight, minHeight), maxHeight)
            let shouldScroll = measuredHeight > maxHeight + 0.5

            if textView.isScrollEnabled != shouldScroll {
                textView.isScrollEnabled = shouldScroll
            }

            DispatchQueue.main.async { [onHeightChange] in
                onHeightChange(clampedHeight)
            }
        }
    }
}

private struct NativeQuickCaptureSendButton: UIViewRepresentable {
    let bridge: QuickCaptureInputBridge
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        let bridge: QuickCaptureInputBridge

        init(bridge: QuickCaptureInputBridge) {
            self.bridge = bridge
        }

        @objc
        func handleTap() {
            bridge.submit()
        }
    }
}

private struct QuickCaptureFieldGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: AppTheme.colors.shadow.opacity(0.08), radius: 14, y: 6)
        }
    }
}

private struct QuickCaptureSendGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: AppTheme.colors.shadow.opacity(0.08), radius: 14, y: 6)
        }
    }
}

private struct QuickCaptureTranscriptPreviewCard: View {
    let text: String
    let isPreparing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isPreparing ? "正在准备语音输入…" : "实时转写")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.48))

            ScrollView(showsIndicators: false) {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(AppTheme.typography.sized(22, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 88, maxHeight: 150)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(QuickCaptureTranscriptPreviewGlassModifier())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("语音转写预览")
        .accessibilityValue(text)
    }
}

private struct QuickCaptureTranscriptPreviewGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: AppTheme.colors.shadow.opacity(0.1), radius: 16, y: 8)
        }
    }
}

private struct DockHubActionGlassModifier: ViewModifier {
    let isAvailable: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isAvailable {
                content
                    .buttonStyle(.glass)
            } else {
                content
                    .glassEffect(
                        .regular.tint(.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
            }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(isAvailable ? 0.84 : 0.72))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: AppTheme.colors.shadow.opacity(0.08), radius: 14, y: 6)
        }
    }
}

private struct QuickCaptureTimeOnlyConfirmationSheet: View {
    let confirmation: QuickCapturePendingConfirmation
    let onConfirm: (Date) -> Void

    @State private var selectedTime: Date?

    init(
        confirmation: QuickCapturePendingConfirmation,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.confirmation = confirmation
        self.onConfirm = onConfirm
        _selectedTime = State(initialValue: confirmation.suggestedReminderAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("确认时间")
                .font(AppTheme.typography.sized(18, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .padding(.top, 20)
                .padding(.bottom, 4)

            TaskEditorTimePickerSheet(
                selectedTime: $selectedTime,
                anchorDate: confirmation.suggestedReminderAt,
                quickPresetMinutes: [],
                showsQuickPresets: false,
                primaryButtonTitle: "确认",
                selectionFeedback: HomeInteractionFeedback.selection,
                primaryFeedback: HomeInteractionFeedback.selection,
                onDismiss: {
                    onConfirm(selectedTime ?? confirmation.suggestedReminderAt)
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct QuickCaptureSheetGlassBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .presentationBackground {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 56, style: .continuous))
                }
        } else {
            content
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

private struct QuickCaptureDateTimeConfirmationSheet: View {
    let confirmation: QuickCapturePendingConfirmation
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onConfirm: (Date) -> Void

    @State private var selectedDate: Date

    init(
        confirmation: QuickCapturePendingConfirmation,
        isSubmitting: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.confirmation = confirmation
        self.isSubmitting = isSubmitting
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _selectedDate = State(initialValue: confirmation.suggestedReminderAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("确认时间")
                .font(AppTheme.typography.sized(20, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            VStack(spacing: 0) {
                TaskEditorDatePickerSheet(
                    selectedDate: selectedDayBinding,
                    selectionFeedback: HomeInteractionFeedback.selection,
                    onDismiss: {}
                )
                .frame(height: TaskEditorDatePickerSheet.preferredHeight)

                Divider()
                    .overlay(AppTheme.colors.separator.opacity(0.2))
                    .padding(.horizontal, 12)

                QuickCaptureInlineTimeRow(selectedDate: $selectedDate)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("取消")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .buttonStyle(QuickCaptureSheetActionButtonStyle())

                Button {
                    onConfirm(selectedDate)
                } label: {
                    Text("确认")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .buttonStyle(QuickCaptureSheetActionButtonStyle(isPrimary: true))
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var selectedDayBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: selectedDate) },
            set: { newDay in
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: selectedDate)
                let minute = calendar.component(.minute, from: selectedDate)
                let merged = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: newDay
                ) ?? newDay
                selectedDate = merged
            }
        )
    }
}

private struct QuickCaptureInlineTimeRow: View {
    @Binding var selectedDate: Date

    var body: some View {
        HStack(spacing: 14) {
            Text("时间")
                .font(AppTheme.typography.sized(16, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.7))
                .lineLimit(1)

            Spacer(minLength: 0)

            DatePicker(
                "时间",
                selection: $selectedDate,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(AppTheme.colors.title)
            .blendMode(.normal)
            .padding(.horizontal, 4)
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickCaptureSheetActionButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.typography.sized(17, weight: .semibold))
            .foregroundStyle(AppTheme.colors.title)
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
            .modifier(QuickCaptureSheetActionGlassModifier(isPrimary: isPrimary))
    }
}

private struct QuickCaptureSheetActionGlassModifier: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    isPrimary ? .regular.interactive() : .regular,
                    in: Capsule(style: .continuous)
                )
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(isPrimary ? AppTheme.colors.pillSurface : AppTheme.colors.surfaceElevated)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isPrimary ? AppTheme.colors.pillOutline : AppTheme.colors.separator.opacity(0.45),
                            lineWidth: 1
                        )
                }
        }
    }
}

private struct QuickCaptureDateTimeConfirmationPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.large])
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
