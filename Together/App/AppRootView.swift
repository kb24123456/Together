import SwiftUI

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        @Bindable var router = appContext.router

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                HomeView(viewModel: appContext.homeViewModel)
            }
            .tabItem {
                Image(systemName: "house.fill")
            }
            .tag(AppTab.home)

            NavigationStack {
                DecisionsView(viewModel: appContext.decisionsViewModel)
            }
            .tabItem {
                Image(systemName: "checklist.checked")
            }
            .tag(AppTab.decisions)

            NavigationStack {
                AnniversariesView(viewModel: appContext.anniversariesViewModel)
            }
            .tabItem {
                Image(systemName: "calendar")
            }
            .tag(AppTab.anniversaries)

            NavigationStack {
                ProfileView(viewModel: appContext.profileViewModel)
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
            }
            .tag(AppTab.profile)
        }
        .sheet(item: $router.activeComposer) { route in
            ComposerPlaceholderSheet(route: route)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
    }
}
