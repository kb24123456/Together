import SwiftUI
import UIKit

private enum AppRootRoute: Hashable {
    case profile
}

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rootNavigationPath = NavigationPath()

    var body: some View {
        @Bindable var router = appContext.router

        NavigationStack(path: $rootNavigationPath) {
            rootSurfaceView(router: router)
                .toolbar {
                    dockToolbar(router: router)
                }
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                .toolbarVisibility(appContext.homeViewModel.isDockHidden ? .hidden : .visible, for: .bottomBar)
                .navigationDestination(for: AppRootRoute.self) { route in
                    switch route {
                    case .profile:
                        ProfileView(viewModel: appContext.profileViewModel)
                    }
                }
        }
        .background(GradientGridBackground())
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
        .sheet(isPresented: $router.isOCRImportPresented) {
            OCRImportView(
                viewModel: OCRImportViewModel(),
                appContext: appContext
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
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
                onProfileTapped: {
                    openProfile(router: router)
                },
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

        if isOverlayActive {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    HomeInteractionFeedback.selection()
                    returnToToday(router: router)
                } label: {
                    Text("今天")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
                .tint(dockSelectionTint)
                .accessibilityLabel("返回今天")
                .accessibilityHint("退出当前视图回到 Today")
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
        }

        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                toggleCalendarSurface(router: router)
            } label: {
                Image(systemName: "calendar")
            }
            .tint(isMonthModeActive ? dockSelectionTint : AppTheme.colors.title)
            .accessibilityLabel(isMonthModeActive ? "关闭月历" : "打开月历")

            if showsRoutinesButton {
                Button {
                    toggleRoutinesSurface(router: router)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .tint(isRoutinesModeActive ? dockSelectionTint : AppTheme.colors.title)
                .accessibilityLabel(isRoutinesModeActive ? "关闭例行事务" : "打开例行事务")
            }

            Button {
                toggleProjectsSurface(router: router)
            } label: {
                Image(systemName: "folder")
            }
            .tint(isProjectsModeActive ? dockSelectionTint : AppTheme.colors.title)
            .accessibilityLabel(isProjectsModeActive ? "关闭项目" : "打开项目")
        }

        ToolbarSpacer(.fixed, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                HomeInteractionFeedback.selection()
                router.isOCRImportPresented = true
            } label: {
                Image(systemName: "doc.text.viewfinder")
            }
            .accessibilityLabel("OCR 导入")
            .accessibilityHint("拍摄或选择纸面笔记生成草稿")
        }

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

    private func openProfile(router: AppRouter) {
        guard router.isProfilePresented == false else { return }
        router.isProfilePresented = true
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
