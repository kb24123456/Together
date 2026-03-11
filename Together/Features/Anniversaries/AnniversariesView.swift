import SwiftUI

struct AnniversariesView: View {
    @Bindable var viewModel: AnniversariesViewModel

    var body: some View {
        ZStack {
            AppTheme.colors.background.ignoresSafeArea()

            Text("纪念日")
                .font(AppTheme.typography.textStyle(.title2, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
        }
        .navigationTitle("纪念日")
        .toolbar(.visible, for: .navigationBar)
        .font(AppTheme.typography.body)
    }
}
