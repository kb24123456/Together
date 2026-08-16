import SwiftUI

/// Editing content hosted by the list-owned periodic task morph container.
struct PeriodicTaskCreationCard: View {
    @Bindable var viewModel: RoutinesViewModel
    let session: PeriodicTaskCreationSession
    let isInteractive: Bool
    let onDiscard: () -> Void
    let onCommit: @MainActor () async -> Void

    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var notes: String
    @State private var showsReminderEditor = false

    private enum Field: Hashable { case title, notes }

    init(
        viewModel: RoutinesViewModel,
        session: PeriodicTaskCreationSession,
        isInteractive: Bool,
        onDiscard: @escaping () -> Void,
        onCommit: @escaping @MainActor () async -> Void
    ) {
        self.viewModel = viewModel
        self.session = session
        self.isInteractive = isInteractive
        self.onDiscard = onDiscard
        self.onCommit = onCommit
        _title = State(initialValue: session.draft.title)
        _notes = State(initialValue: session.draft.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: AppTheme.spacing.sm) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        AppTheme.colors.body.opacity(0.30),
                        lineWidth: 1.2
                    )
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    TextField("定期任务标题", text: $title, axis: .vertical)
                        .font(AppTheme.typography.scaled(17, weight: .semibold, relativeTo: .headline))
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                        .onChange(of: title) { _, value in
                            viewModel.updateCreationDraft { $0.title = value }
                        }

                    TextField("添加备注", text: $notes, axis: .vertical)
                        .font(AppTheme.typography.scaled(14, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .notes)
                        .onChange(of: notes) { _, value in
                            viewModel.updateCreationDraft {
                                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                $0.notes = trimmed.isEmpty ? nil : value
                            }
                        }
                }
            }

            Picker(
                "周期",
                selection: Binding(
                    get: { session.draft.cycle },
                    set: { cycle in viewModel.updateCreationDraft { $0.cycle = cycle } }
                )
            ) {
                ForEach(PeriodicCycle.allCases, id: \.self) { cycle in
                    Text(cycle.title).tag(cycle)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("选择定期任务的重复周期")

            Button {
                focusedField = nil
                if session.draft.reminderRules.isEmpty {
                    viewModel.updateCreationDraft {
                        $0.reminderRules = [RoutinesViewModel.defaultRule(for: $0.cycle)]
                    }
                }
                showsReminderEditor.toggle()
            } label: {
                Label(
                    session.draft.reminderRules.isEmpty ? "设置目标与提醒" : "编辑目标与提醒",
                    systemImage: "bell"
                )
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)

            if showsReminderEditor {
                RoutinesReminderRulePicker(
                    rule: Binding(
                        get: {
                            viewModel.creationSession?.draft.reminderRules.first
                                ?? RoutinesViewModel.defaultRule(for: session.draft.cycle)
                        },
                        set: { rule in
                            viewModel.updateCreationDraft { $0.reminderRules = rule.isEmpty ? [] : [rule] }
                        }
                    ),
                    cycle: viewModel.creationSession?.draft.cycle ?? session.draft.cycle,
                    onDelete: {
                        viewModel.updateCreationDraft { $0.reminderRules = [] }
                        showsReminderEditor = false
                    }
                )
                .frame(height: 300)
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("放弃", role: .cancel) {
                    focusedField = nil
                    onDiscard()
                }
                .frame(minWidth: 72, minHeight: 44)

                Button {
                    focusedField = nil
                    Task { await onCommit() }
                } label: {
                    Group {
                        if session.phase == .committing || session.phase == .committed {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("添加")
                        }
                    }
                    .font(AppTheme.typography.sized(15, weight: .bold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(AppTheme.colors.title))
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.phase != .editing)
                .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
            }
        }
        .padding(
            EdgeInsets(
                top: 2,
                leading: 0,
                bottom: AppTheme.spacing.lg,
                trailing: 0
            )
        )
        .onAppear { updateFocus(isInteractive) }
        .onChange(of: isInteractive) { _, value in updateFocus(value) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新建定期任务")
    }

    private func updateFocus(_ shouldFocus: Bool) {
        if shouldFocus {
            Task { @MainActor in
                await Task.yield()
                focusedField = .title
            }
        } else {
            focusedField = nil
            showsReminderEditor = false
        }
    }
}
