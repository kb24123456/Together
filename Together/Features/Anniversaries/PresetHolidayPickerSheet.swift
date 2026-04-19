import SwiftUI

struct PresetHolidayPickerSheet: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<PresetHolidayID> = []

    private var viewModel: ImportantDatesViewModel {
        appContext.importantDatesViewModel
    }

    var body: some View {
        NavigationStack {
            List(PresetHolidayID.allCases, id: \.self) { preset in
                Button {
                    if selectedIDs.contains(preset) {
                        selectedIDs.remove(preset)
                    } else {
                        selectedIDs.insert(preset)
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedIDs.contains(preset) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedIDs.contains(preset) ? AppTheme.colors.coral : .secondary)
                        Text(preset.defaultTitle).foregroundStyle(.primary)
                        Spacer()
                        Text(nextDateLabel(for: preset)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("常见节日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save() }.disabled(selectedIDs.isEmpty)
                }
            }
        }
        .onAppear { seedSelection() }
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
            for preset in selectedIDs where existing[preset] == nil {
                let event = ImportantDate(
                    id: UUID(), spaceID: spaceID, creatorID: myID,
                    kind: .holiday, title: preset.defaultTitle,
                    dateValue: computeSeedDate(for: preset),
                    recurrence: preset.recurrence,
                    notifyDaysBefore: 7, notifyOnDay: true,
                    icon: preset.defaultIcon, presetHolidayID: preset,
                    updatedAt: .now
                )
                await viewModel.save(event)
            }
            for (preset, event) in existing where !selectedIDs.contains(preset) {
                await viewModel.delete(event.id)
            }
            dismiss()
        }
    }
}
