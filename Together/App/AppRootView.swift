import SwiftUI

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        @Bindable var router = appContext.router

        TabView(selection: $router.selectedTab) {
            Tab(value: .home) {
                NavigationStack {
                    HomeView(viewModel: appContext.homeViewModel)
                }
            } label: {
                Image(systemName: "checkmark.square")
                    .symbolVariant(.none)
                    .font(.system(size: 19, weight: .light))
                    .accessibilityLabel("首页")
            }

            Tab(value: .decisions) {
                NavigationStack {
                    DecisionsView(viewModel: appContext.decisionsViewModel)
                }
            } label: {
                Image(systemName: "bubble.and.pencil.rtl")
                    .symbolVariant(.none)
                    .font(.system(size: 19, weight: .light))
                    .accessibilityLabel("决策")
            }

            Tab(value: .anniversaries) {
                NavigationStack {
                    AnniversariesView(viewModel: appContext.anniversariesViewModel)
                }
            } label: {
                Image(systemName: "heart.text.square")
                    .symbolVariant(.none)
                    .font(.system(size: 19, weight: .light))
                    .accessibilityLabel("纪念日")
            }

            Tab(value: .profile) {
                NavigationStack {
                    ProfileView(viewModel: appContext.profileViewModel)
                }
            } label: {
                Image(systemName: "suit.heart")
                    .symbolVariant(.none)
                    .font(.system(size: 19, weight: .light))
                    .accessibilityLabel("我")
            }
        }
        .sheet(item: $router.activeComposer) { route in
            ComposerPlaceholderSheet(route: route)
        }
        .environment(\.symbolVariants, .none)
        .background(AppTheme.colors.background.ignoresSafeArea())
        .font(AppTheme.typography.body)
        .tint(AppTheme.colors.title)
    }
}
