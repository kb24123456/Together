import SwiftUI

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        @Bindable var router = appContext.router

        TabView(selection: $router.selectedTab) {
            Tab("首页", systemImage: "house.fill", value: .home) {
                NavigationStack {
                    HomeView(viewModel: appContext.homeViewModel)
                }
            }

            Tab("决策", systemImage: "checklist.checked", value: .decisions) {
                NavigationStack {
                    DecisionsView(viewModel: appContext.decisionsViewModel)
                }
            }

            Tab("纪念日", systemImage: "calendar", value: .anniversaries) {
                NavigationStack {
                    AnniversariesView(viewModel: appContext.anniversariesViewModel)
                }
            }

            Tab("我", systemImage: "person.crop.circle", value: .profile) {
                NavigationStack {
                    ProfileView(viewModel: appContext.profileViewModel)
                }
            }
        }
        .sheet(item: $router.activeComposer) { route in
            ComposerPlaceholderSheet(route: route)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
    }
}
