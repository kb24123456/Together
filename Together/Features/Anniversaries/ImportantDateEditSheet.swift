import SwiftUI

/// 编辑/新建纪念日 sheet。
/// 设计风格：参考 Profile 页面 ——
/// - GradientGrid 背景
/// - ProfileSettingsGroupCard 风格分组（灰小字 label + 透明列表 + 底部 hairline）
/// - 56pt minHeight row（左 title + 右 input/value），与 ProfileSettingsRow 保持一致
struct ImportantDateEditSheet: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State var event: ImportantDate

    private let notifyOptions = ImportantDate.validNotifyDaysBefore

    var body: some View {
        NavigationStack {
            ZStack {
                GradientGridBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.spacing.lg) {
                        titleGroup
                        dateGroup
                        notifyGroup
                        if case .birthday = event.kind {
                            birthdayHint
                        }
                    }
                    .padding(.top, AppTheme.spacing.lg)
                    .padding(.bottom, AppTheme.spacing.xxl)
                }
            }
            .navigationTitle("编辑纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppTheme.colors.body)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                        .foregroundStyle(event.title.isEmpty ? AppTheme.colors.textTertiary : AppTheme.colors.title)
                        .disabled(event.title.isEmpty)
                }
            }
        }
    }

    // MARK: - Groups (Profile 风：灰 label + 无背景 list + bottom hairline)

    private var titleGroup: some View {
        ProfileSettingsGroupCard(title: "标题") {
            rowShell {
                TextField("纪念日名称", text: $event.title)
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var dateGroup: some View {
        ProfileSettingsGroupCard(title: "日期") {
            rowShell(label: "日期") {
                DatePicker("", selection: $event.dateValue, displayedComponents: .date)
                    .labelsHidden()
                    .tint(AppTheme.colors.pairAccent)
            }
            inlineDivider
            rowShell(label: "重复") {
                Picker("", selection: recurrenceSelection) {
                    ForEach(recurrenceOptions, id: \.self) { recurrence in
                        Text(recurrenceTitle(for: recurrence)).tag(recurrence)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.colors.title)
            }
        }
    }

    private var notifyGroup: some View {
        ProfileSettingsGroupCard(title: "提醒") {
            rowShell(label: "提前几天") {
                Picker("", selection: $event.notifyDaysBefore) {
                    ForEach(notifyOptions, id: \.self) { day in
                        Text("\(day) 天").tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.colors.title)
            }
            inlineDivider
            rowShell(label: "当天提醒") {
                Toggle("", isOn: $event.notifyOnDay)
                    .labelsHidden()
                    .tint(AppTheme.colors.selectionTint)
            }
        }
    }

    // MARK: - Row shell（与 ProfileSettingsRow 一致：56pt minHeight、左 title + 右 accessory）

    private func rowShell<Accessory: View>(
        label: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            if let label {
                Text(label)
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(2)
                Spacer(minLength: AppTheme.spacing.md)
            }
            accessory()
                .frame(maxWidth: label == nil ? .infinity : nil, alignment: .trailing)
        }
        .padding(.vertical, AppTheme.spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: label == nil ? .leading : .center)
        .contentShape(Rectangle())
    }

    private var inlineDivider: some View {
        Rectangle()
            .fill(AppTheme.colors.hairline)
            .frame(height: 0.5)
    }

    private var birthdayHint: some View {
        HStack(spacing: AppTheme.spacing.xs) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.colors.textTertiary)
            Text("生日不能修改所属用户")
                .font(AppTheme.typography.cardCaption)
                .foregroundStyle(AppTheme.colors.bodySecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacing.xs)
    }

    private func save() {
        var updated = event
        updated.recurrence = ImportantDate.normalizedRecurrence(updated.recurrence, for: updated.kind)
        updated.updatedAt = .now
        Task {
            await appContext.importantDatesViewModel.save(updated)
            dismiss()
        }
    }

    private var recurrenceOptions: [Recurrence] {
        ImportantDate.editableRecurrences(for: event.kind)
    }

    private var recurrenceSelection: Binding<Recurrence> {
        Binding(
            get: {
                ImportantDate.normalizedRecurrence(event.recurrence, for: event.kind)
            },
            set: { newValue in
                event.recurrence = ImportantDate.normalizedRecurrence(newValue, for: event.kind)
            }
        )
    }

    private func recurrenceTitle(for recurrence: Recurrence) -> String {
        switch recurrence {
        case .none: return "一次性"
        case .solarAnnual: return "公历"
        case .lunarAnnual: return "农历"
        }
    }
}
