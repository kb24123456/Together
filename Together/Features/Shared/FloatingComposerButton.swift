import SwiftUI

struct FloatingComposerButton: View {
    let onCreateItem: () -> Void
    let onCreateDecision: () -> Void

    var body: some View {
        Menu {
            Button("发请求", systemImage: "square.and.pencil") {
                onCreateItem()
            }

            Button("发决策", systemImage: "checklist") {
                onCreateDecision()
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(AppTheme.colors.accent, in: Circle())
                .shadow(color: AppTheme.colors.accent.opacity(0.25), radius: 12, y: 8)
        }
        .menuStyle(.button)
    }
}
