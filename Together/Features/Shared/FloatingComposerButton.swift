import SwiftUI

struct FloatingComposerButton: View {
    let onCreateTask: () -> Void
    let onCreateProject: () -> Void

    private let floatingPink = Color(red: 0.91, green: 0.39, blue: 0.60)

    var body: some View {
        Menu {
            Button("新建任务", systemImage: "square.and.pencil") {
                onCreateTask()
            }

            Button("新建项目", systemImage: "folder.badge.plus") {
                onCreateProject()
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
        .accessibilityLabel("新建")
        .accessibilityHint("打开菜单选择新建任务或项目")
    }
}
