import SwiftUI

struct FloatingComposerButton: View {
    let onCreateItem: () -> Void
    let onCreateDecision: () -> Void

    private let floatingPink = Color(red: 0.91, green: 0.39, blue: 0.60)

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
                .font(AppTheme.typography.textStyle(.title2, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(floatingPink, in: Circle())
                .shadow(color: floatingPink.opacity(0.25), radius: 12, y: 8)
        }
        .menuStyle(.button)
    }
}
