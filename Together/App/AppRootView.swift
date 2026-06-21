import SwiftUI
import UIKit

private enum AppRootRoute: Hashable {
    case profile
    case completedHistory(CompletedHistoryFilter)
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
                    topToolbar(router: router)
                    dockToolbar(router: router)
                }
                .navigationTitle(navigationTitle(for: router))
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
        .sheet(isPresented: $router.isOCRImportPresented) {
            OCRImportView(
                viewModel: OCRImportViewModel(),
                appContext: appContext
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(36)
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
        case .today, .routines:
            HomeView(
                viewModel: appContext.homeViewModel,
                projectsViewModel: appContext.projectsViewModel,
                routinesViewModel: appContext.routinesViewModel,
                isProjectModePresented: false,
                isRoutinesModePresented: router.isRoutinesModePresented,
                onProfileTapped: {
                    openProfile(router: router)
                },
                onCreateTaskTapped: {
                    router.pendingComposerTitle = nil
                    router.activeComposer = .newTask
                },
                onCompletedHistoryTapped: { filter in
                    rootNavigationPath.append(AppRootRoute.completedHistory(filter))
                }
            )
        case .calendar, .projects:
            EmptyView()
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
                    ToolbarIconActionLabel(systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(isRoutinesModeActive ? dockSelectionTint : AppTheme.colors.title)
                .accessibilityLabel(isRoutinesModeActive ? "关闭例行事务" : "打开例行事务")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HomeInteractionFeedback.selection()
                openProfile(router: router)
            } label: {
                let avatar = appContext.homeViewModel.currentUserAvatar
                ToolbarAvatarActionLabel(
                    avatarAsset: avatar.avatarAsset,
                    displayName: avatar.displayName,
                    overrideImage: avatar.overrideImage
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开个人页")
            .accessibilityHint("查看个人资料和设置")
        }
    }

    @ToolbarContentBuilder
    private func dockToolbar(router: AppRouter) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                HomeInteractionFeedback.selection()
                rootNavigationPath.append(AppRootRoute.completedHistory(.week))
            } label: {
                ToolbarIconActionLabel(systemImage: "checkmark.circle")
            }
            .accessibilityLabel("已完成任务")
            .accessibilityHint("查看全部已完成任务")
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                HomeInteractionFeedback.selection()
                router.isOCRImportPresented = true
            } label: {
                ToolbarIconActionLabel(systemImage: "doc.text.viewfinder")
            }
            .accessibilityLabel("OCR 导入")
            .accessibilityHint("拍摄或选择纸面笔记生成草稿")

            Button {
                HomeInteractionFeedback.selection()
                openContextualComposer(router: router)
            } label: {
                ToolbarIconActionLabel(systemImage: "plus")
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
        case .routines:
            toggleRoutinesSurface(router: router)
        case .calendar, .projects:
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
        case .today, .calendar, .projects:
            router.activeComposer = .newTask
        case .routines:
            router.activeComposer = .newPeriodicTask
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

    private func navigationTitle(for router: AppRouter) -> String {
        switch router.currentSurface {
        case .routines:
            return "例行任务"
        case .today, .calendar, .projects:
            return "任务"
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
