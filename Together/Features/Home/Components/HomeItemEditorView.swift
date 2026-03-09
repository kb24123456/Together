import SwiftUI

struct HomeItemEditorView: View {
    let item: Item
    @Binding var draft: HomeEditorDraft
    let namespace: Namespace.ID
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                header
                titleField
                noteField
                metadataSection
                roleSection
                footerActions
            }
            .padding(AppTheme.spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 520)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
                .matchedGeometryEffect(id: item.id, in: namespace)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(AppTheme.colors.outline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 26, y: 10)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Toggle(isOn: $draft.isPinned) {
                Text("置顶")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.colors.title)
            }
            .toggleStyle(.switch)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.colors.body)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.colors.background, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var titleField: some View {
        TextField("事项标题", text: $draft.title, axis: .vertical)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.colors.title)
            .textFieldStyle(.plain)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("补充说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.colors.body)

            TextField("写下细节、提醒或补充上下文", text: $draft.notes, axis: .vertical)
                .font(.body)
                .foregroundStyle(AppTheme.colors.title)
                .padding(AppTheme.spacing.md)
                .background(AppTheme.colors.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            DatePicker("执行时间", selection: $draft.dueAt)

            TextField("地理位置", text: $draft.locationText)
                .textFieldStyle(.roundedBorder)

            Picker("优先级", selection: $draft.priority) {
                ForEach(ItemPriority.allCases, id: \.self) { priority in
                    Text(priority.title).tag(priority)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("由谁执行")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.colors.body)

            Picker("执行角色", selection: $draft.executionRole) {
                Text("我负责").tag(ItemExecutionRole.initiator)
                Text("对方负责").tag(ItemExecutionRole.recipient)
                Text("共同执行").tag(ItemExecutionRole.both)
            }
            .pickerStyle(.segmented)
        }
    }

    private var footerActions: some View {
        HStack(spacing: AppTheme.spacing.md) {
            Button("关闭", action: onClose)
                .buttonStyle(.bordered)

            Spacer()

            Button("保存", action: onSave)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.colors.accent)
        }
    }
}
