import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var profileNavigationPath = NavigationPath()

    var body: some View {
        @Bindable var router = appContext.router

        // 显式 read isPremium 建立 @Observable 追踪依赖，确保 body re-evaluate 时
        // .onChange(of:) 能检测到变化（修 Phase 2 真机 onChange 不触发的 bug）
        let isPremiumNow = appContext.container.premiumGate.isPremium

        NavigationStack {
            rootSurfaceView(router: router)
                .toolbar {
                    dockToolbar(router: router)
                }
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                .toolbarVisibility(appContext.homeViewModel.isDockHidden ? .hidden : .visible, for: .bottomBar)
        }
        .background(GradientGridBackground())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $router.isProfilePresented) {
            NavigationStack(path: $profileNavigationPath) {
                ProfileView(viewModel: appContext.profileViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("日志") {
                                HomeInteractionFeedback.selection()
                                profileNavigationPath.append(ProfileRoute.completedHistory)
                            }
                            .font(AppTheme.typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(AppTheme.colors.title)
                            .accessibilityHint("查看已完成任务")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") {
                                router.isProfilePresented = false
                            }
                            .font(AppTheme.typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(AppTheme.colors.title)
                        }
                }
            }
            .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
            .paywallRootSheet(appContext)   // fullScreenCover 内再挂一份，否则 paywall sheet 会被 Profile cover 挡住
            .onDisappear {
                profileNavigationPath = NavigationPath()
            }
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
        .environment(\.symbolVariants, .none)
        .font(AppTheme.typography.body)
        .tint(AppTheme.colors.title)
        .preferredColorScheme(appContext.appearanceManager.resolvedColorScheme)
        .onChange(of: appContext.projectsViewModel.pendingUpsellTrigger) { _, new in
            if let trigger = new {
                appContext.rootPaywallPresentation.requestTrigger(trigger)
            }
        }
        .onChange(of: isPremiumNow) { oldValue, newValue in
            // Pro → Free 运行时：数据面停同步 + UI 面 lapse sheet
            Task {
                await appContext.handlePremiumStatusChange(
                    wasPremium: oldValue,
                    isPremium: newValue
                )
            }
        }
        .paywallRootSheet(appContext)
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

    // MARK: - Native bottom toolbar

    @ToolbarContentBuilder
    private func dockToolbar(router: AppRouter) -> some ToolbarContent {
        let isOverlayActive = router.currentSurface != .today
        let isMonthModeActive = appContext.homeViewModel.isMonthMode
        let isRoutinesModeActive = router.currentSurface == .routines
        let isProjectsModeActive = router.isProjectModePresented
        let showsRoutinesButton = appContext.sessionStore.activeMode == .single

        ToolbarItem(placement: .bottomBar) {
            Button {
                HomeInteractionFeedback.selection()
                if isOverlayActive {
                    returnToToday(router: router)
                } else {
                    router.isProfilePresented = true
                }
            } label: {
                Text(isOverlayActive ? "今天" : "我的")
                    .font(AppTheme.typography.sized(15, weight: .semibold))
            }
            .tint(isOverlayActive ? AppTheme.colors.pairAccent : AppTheme.colors.title)
            .accessibilityLabel(isOverlayActive ? "返回今天" : "打开我的")
            .accessibilityHint(isOverlayActive ? "退出当前视图回到 Today" : "打开个人页")
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                toggleCalendarSurface(router: router)
            } label: {
                Image(systemName: "calendar")
            }
            .tint(isMonthModeActive ? AppTheme.colors.pairAccent : AppTheme.colors.title)
            .accessibilityLabel(isMonthModeActive ? "关闭月历" : "打开月历")

            if showsRoutinesButton {
                Button {
                    toggleRoutinesSurface(router: router)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .tint(isRoutinesModeActive ? AppTheme.colors.pairAccent : AppTheme.colors.title)
                .accessibilityLabel(isRoutinesModeActive ? "关闭例行事务" : "打开例行事务")
            }

            Button {
                toggleProjectsSurface(router: router)
            } label: {
                Image(systemName: "folder")
            }
            .tint(isProjectsModeActive ? AppTheme.colors.pairAccent : AppTheme.colors.title)
            .accessibilityLabel(isProjectsModeActive ? "关闭项目" : "打开项目")
        }

        ToolbarSpacer(.fixed, placement: .bottomBar)

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

    private var projectModeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private func returnToToday(router: AppRouter) {
        let surface = router.currentSurface
        switch surface {
        case .calendar:
            toggleCalendarSurface(router: router)
        case .routines:
            toggleRoutinesSurface(router: router)
        case .projects:
            closeProjectsMode(router: router)
        case .today:
            break
        }
    }

    private func openContextualComposer(router: AppRouter) {
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

    private func openProjectsMode(router: AppRouter) {
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }
        guard router.isProjectModePresented == false else { return }

        HomeInteractionFeedback.selection()
        withAnimation(projectModeAnimation) {
            appContext.homeViewModel.setCalendarDisplayMode(.week)
            router.currentSurface = .projects
        }
    }

    private func closeProjectsMode(router: AppRouter) {
        guard router.isProjectModePresented else { return }

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
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }

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
        guard router.isProfilePresented == false else { return }
        guard router.activeComposer == nil else { return }

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
