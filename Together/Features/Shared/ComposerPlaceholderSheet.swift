import SwiftUI

struct ComposerPlaceholderSheet: View {
    let route: ComposerRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                Text(route == .newItem ? "发请求" : "发决策")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.colors.title)

                Text("本轮只完成工程脚手架。这里保留为占位入口，后续接真实表单与发送流程。")
                    .font(.body)
                    .foregroundStyle(AppTheme.colors.body)

                Spacer()
            }
            .padding(AppTheme.spacing.xl)
            .navigationTitle("占位流程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
