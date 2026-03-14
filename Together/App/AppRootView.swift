import SwiftUI

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        @Bindable var router = appContext.router

        ZStack(alignment: .bottom) {
            ProjectsView(
                viewModel: appContext.projectsViewModel,
                style: .layer
            )
            .opacity(router.isProjectLayerPresented ? 1 : 0)
            .animation(.easeInOut(duration: 0.22), value: router.isProjectLayerPresented)

            NavigationStack {
                HomeView(
                    viewModel: appContext.homeViewModel,
                    isProjectLayerPresented: router.isProjectLayerPresented
                )
            }

        }
        .background(
            Group {
                if router.isProjectLayerPresented {
                    AppTheme.colors.projectLayerBackground.ignoresSafeArea()
                } else {
                    AppTheme.colors.homeBackground.ignoresSafeArea()
                }
            }
        )
        .safeAreaInset(edge: .bottom, spacing: 10) {
            HomeDockBar(
                isProjectLayerPresented: router.isProjectLayerPresented,
                onProfileTapped: {
                    router.isProjectLayerPresented = false
                    router.isProfilePresented = true
                },
                onComposeTapped: {
                    router.isProjectLayerPresented = false
                    router.activeComposer = .newTask
                },
                onProjectsTapped: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        router.isProjectLayerPresented.toggle()
                    }
                }
            )
        }
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
        }
        .sheet(item: $router.activeComposer) { route in
            ComposerPlaceholderSheet(
                route: route,
                appContext: appContext
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
