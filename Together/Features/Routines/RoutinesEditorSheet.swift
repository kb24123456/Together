import SwiftUI

struct RoutinesEditorSheet: View {
    let viewModel: RoutinesViewModel

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var cycle: PeriodicCycle = .monthly
    @State private var reminderEnabled = false
    @State private var reminderRules: [PeriodicReminderRule] = []
    @State private var showDeleteConfirmation = false

    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool {
        viewModel.editingTask != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacing.lg) {
                    titleSection
                    cycleSection
                    reminderSection

                    if isEditing {
                        deleteSection
                    }
                }
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.top, AppTheme.spacing.md)
            }
            .background(AppTheme.colors.background)
            .navigationTitle(isEditing ? "编辑例行事务" : "新建例行事务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                        viewModel.dismissEditor()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let task = viewModel.editingTask {
                title = task.title
                notes = task.notes ?? ""
                cycle = task.cycle
                reminderRules = task.reminderRules
                reminderEnabled = !task.reminderRules.isEmpty
            }
        }
        .confirmationDialog("确定删除？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                deleteAndDismiss()
            }
        } message: {
            Text("删除后无法恢复")
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            TextField("事务名称", text: $title)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .padding(AppTheme.spacing.md)
                .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.colors.outline)
                }

            TextField("备注（可选）", text: $notes, axis: .vertical)
                .font(AppTheme.typography.textStyle(.subheadline))
                .lineLimit(3...6)
                .padding(AppTheme.spacing.md)
                .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.colors.outline)
                }
        }
    }

    private var cycleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("周期")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                .foregroundStyle(AppTheme.colors.body)

            Picker("周期", selection: $cycle) {
                ForEach(PeriodicCycle.allCases, id: \.self) { c in
                    Text(c.title).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(AppTheme.spacing.lg)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Toggle(isOn: $reminderEnabled) {
                Text("设置提醒")
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body)
            }
            .tint(AppTheme.colors.accent)
            .onChange(of: reminderEnabled) { _, enabled in
                if enabled && reminderRules.isEmpty {
                    reminderRules.append(defaultReminderRule(for: cycle))
                } else if !enabled {
                    reminderRules.removeAll()
                }
            }

            if reminderEnabled {
                ForEach(reminderRules.indices, id: \.self) { index in
                    RoutinesReminderRulePicker(
                        rule: $reminderRules[index],
                        cycle: cycle,
                        onDelete: reminderRules.count > 1 ? {
                            reminderRules.remove(at: index)
                        } : nil
                    )
                }

                Button {
                    reminderRules.append(defaultReminderRule(for: cycle))
                } label: {
                    Label("添加提醒规则", systemImage: "plus.circle")
                        .font(AppTheme.typography.textStyle(.subheadline))
                        .foregroundStyle(AppTheme.colors.accent)
                }
            }
        }
        .padding(AppTheme.spacing.lg)
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Text("删除例行事务")
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(AppTheme.colors.danger)
                .frame(maxWidth: .infinity)
                .padding(AppTheme.spacing.md)
        }
        .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(AppTheme.colors.outline)
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let draft = PeriodicTaskDraft(
            title: trimmedTitle,
            notes: notes.isEmpty ? nil : notes,
            cycle: cycle,
            reminderRules: reminderEnabled ? reminderRules : []
        )

        Task {
            if let existing = viewModel.editingTask {
                await viewModel.updateTask(taskID: existing.id, draft: draft)
            } else {
                await viewModel.createTask(draft: draft)
            }
            dismiss()
            viewModel.dismissEditor()
        }
    }

    private func deleteAndDismiss() {
        guard let task = viewModel.editingTask else { return }
        Task {
            await viewModel.deleteTask(taskID: task.id)
            dismiss()
            viewModel.dismissEditor()
        }
    }

    private func defaultReminderRule(for cycle: PeriodicCycle) -> PeriodicReminderRule {
        switch cycle {
        case .weekly:
            return PeriodicReminderRule(timing: .daysBeforeEnd(1))
        case .monthly:
            return PeriodicReminderRule(timing: .dayOfPeriod(20))
        case .quarterly:
            return PeriodicReminderRule(timing: .daysBeforeEnd(14))
        case .yearly:
            return PeriodicReminderRule(timing: .daysBeforeEnd(30))
        }
    }
}
