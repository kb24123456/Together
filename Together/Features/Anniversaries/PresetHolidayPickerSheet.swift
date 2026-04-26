import SwiftUI

struct PresetHolidayPickerSheet: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    /// 当 picker 内的批量保存因配额停止时由父视图收到通知，
    /// 父视图在 `onDismiss` 里 requestQuotaUpsell——保证 sheet 关闭动画完成后才弹 paywall，
    /// 避开 iOS 多 sheet 冲突。
    var onQuotaHit: (() -> Void)? = nil

    @State private var selectedIDs: Set<PresetHolidayID> = []

    private var viewModel: ImportantDatesViewModel {
        appContext.importantDatesViewModel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientGridBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.spacing.lg) {
                        ProfileSettingsGroupCard(title: "勾选要添加的节日") {
                            ForEach(Array(PresetHolidayID.allCases.enumerated()), id: \.element) { index, preset in
                                if index > 0 {
                                    Rectangle()
                                        .fill(AppTheme.colors.hairline)
                                        .frame(height: 0.5)
                                }
                                presetRow(preset)
                            }
                        }
                    }
                    .padding(.top, AppTheme.spacing.lg)
                    .padding(.bottom, AppTheme.spacing.xxl)
                }
            }
            .navigationTitle("常见节日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppTheme.colors.body)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save() }
                        .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                        .foregroundStyle(selectedIDs.isEmpty ? AppTheme.colors.textTertiary : AppTheme.colors.title)
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { seedSelection() }
    }

    private func presetRow(_ preset: PresetHolidayID) -> some View {
        let isChecked = selectedIDs.contains(preset)
        return Button {
            if isChecked {
                selectedIDs.remove(preset)
            } else {
                selectedIDs.insert(preset)
            }
        } label: {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isChecked ? AppTheme.colors.selectionTint : AppTheme.colors.textTertiary)
                Text(preset.defaultTitle)
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)
                Spacer(minLength: 0)
                Text(nextDateLabel(for: preset))
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.64))
            }
            .padding(.vertical, AppTheme.spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func seedSelection() {
        let existing = viewModel.events.compactMap { $0.presetHolidayID }
        selectedIDs = Set(existing)
    }

    private func nextDateLabel(for preset: PresetHolidayID) -> String {
        let seedDate = computeSeedDate(for: preset)
        let event = ImportantDate(
            id: UUID(), spaceID: UUID(), creatorID: UUID(),
            kind: .holiday, title: preset.defaultTitle, dateValue: seedDate,
            recurrence: preset.recurrence, notifyDaysBefore: 7, notifyOnDay: true,
            icon: nil, presetHolidayID: preset, updatedAt: .now
        )
        guard let next = event.nextOccurrence(after: .now) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/M/d"
        return fmt.string(from: next)
    }

    /// 内置 seed date：preset 的首次发生参考日期（用于 nextOccurrence 计算）
    private func computeSeedDate(for preset: PresetHolidayID) -> Date {
        let (month, day) = preset.monthDay
        let cal: Calendar
        switch preset.recurrence {
        case .solarAnnual:
            cal = Calendar(identifier: .gregorian)
        case .lunarAnnual:
            cal = Calendar(identifier: .chinese)
        case .none:
            return .now
        }
        let year = cal.component(.year, from: .now)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return cal.date(from: comps) ?? .now
    }

    private func save() {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let existing = Dictionary(uniqueKeysWithValues: viewModel.events.compactMap { e -> (PresetHolidayID, ImportantDate)? in
            guard let pid = e.presetHolidayID else { return nil }
            return (pid, e)
        })

        Task {
            var quotaHit = false
            for preset in selectedIDs where existing[preset] == nil {
                if !viewModel.canCreateAnotherForCurrentUser() {
                    quotaHit = true
                    break
                }
                let event = ImportantDate(
                    id: UUID(), spaceID: spaceID, creatorID: myID,
                    kind: .holiday, title: preset.defaultTitle,
                    dateValue: computeSeedDate(for: preset),
                    recurrence: preset.recurrence,
                    notifyDaysBefore: 7, notifyOnDay: true,
                    icon: preset.defaultIcon, presetHolidayID: preset,
                    updatedAt: .now,
                    isPinnedToToday: true   // Spec §6.3 — preset holidays auto-pinned for Today.
                )
                await viewModel.save(event)
            }
            for (preset, event) in existing where !selectedIDs.contains(preset) {
                await viewModel.delete(event.id)
            }
            if quotaHit {
                onQuotaHit?()
            }
            dismiss()
        }
    }
}
