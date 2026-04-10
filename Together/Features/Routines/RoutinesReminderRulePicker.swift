import SwiftUI

struct RoutinesReminderRulePicker: View {
    @Binding var rule: PeriodicReminderRule
    let cycle: PeriodicCycle
    var onDelete: (() -> Void)?

    @State private var timingType: TimingType = .daysBeforeEnd
    @State private var dayValue: Int = 3
    @State private var selectedHour: Int = 9
    @State private var selectedMinute: Int = 0

    enum TimingType: String, CaseIterable {
        case dayOfPeriod
        case businessDayOfPeriod
        case daysBeforeEnd

        var label: String {
            switch self {
            case .dayOfPeriod: "第 N 天"
            case .businessDayOfPeriod: "第 N 个工作日"
            case .daysBeforeEnd: "截止前 N 天"
            }
        }

        static func availableTypes(for cycle: PeriodicCycle) -> [TimingType] {
            switch cycle {
            case .weekly:
                return [.dayOfPeriod, .daysBeforeEnd]
            case .monthly:
                return [.dayOfPeriod, .businessDayOfPeriod, .daysBeforeEnd]
            case .quarterly:
                return [.dayOfPeriod, .businessDayOfPeriod, .daysBeforeEnd]
            case .yearly:
                return [.dayOfPeriod, .daysBeforeEnd]
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            HStack {
                Text("提醒规则")
                    .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                Spacer()
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppTheme.colors.danger)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                }
            }

            timingTypePicker
            dayValuePicker
            timePicker
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { loadFromRule() }
        .onChange(of: timingType) { _, _ in syncToRule() }
        .onChange(of: dayValue) { _, _ in syncToRule() }
        .onChange(of: selectedHour) { _, _ in syncToRule() }
        .onChange(of: selectedMinute) { _, _ in syncToRule() }
    }

    private var timingTypePicker: some View {
        let types = TimingType.availableTypes(for: cycle)
        return Picker("规则类型", selection: $timingType) {
            ForEach(types, id: \.self) { type in
                Text(type.label).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    private var dayValuePicker: some View {
        HStack {
            Text(dayValueLabel)
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.body)

            Spacer()

            Stepper(value: $dayValue, in: dayValueRange) {
                Text("\(dayValue)")
                    .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .monospacedDigit()
            }
            .frame(width: 140)
        }
    }

    private var timePicker: some View {
        HStack {
            Text("提醒时间")
                .font(AppTheme.typography.textStyle(.subheadline))
                .foregroundStyle(AppTheme.colors.body)

            Spacer()

            HStack(spacing: 4) {
                Picker("时", selection: $selectedHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 52, height: 80)
                .clipped()

                Text(":")
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body)

                Picker("分", selection: $selectedMinute) {
                    ForEach([0, 15, 30, 45], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 52, height: 80)
                .clipped()
            }
        }
    }

    // MARK: - Helpers

    private var dayValueLabel: String {
        switch timingType {
        case .dayOfPeriod:
            switch cycle {
            case .weekly: "每周第"
            case .monthly: "每月第"
            case .quarterly: "每季度第"
            case .yearly: "每年第"
            }
        case .businessDayOfPeriod: "第"
        case .daysBeforeEnd: "截止前"
        }
    }

    private var dayValueRange: ClosedRange<Int> {
        switch timingType {
        case .dayOfPeriod:
            switch cycle {
            case .weekly: 1...7
            case .monthly: 1...28
            case .quarterly: 1...90
            case .yearly: 1...365
            }
        case .businessDayOfPeriod:
            1...20
        case .daysBeforeEnd:
            switch cycle {
            case .weekly: 1...6
            case .monthly: 1...27
            case .quarterly: 1...89
            case .yearly: 1...364
            }
        }
    }

    private func loadFromRule() {
        switch rule.timing {
        case .dayOfPeriod(let day):
            timingType = .dayOfPeriod
            dayValue = day
        case .businessDayOfPeriod(let day):
            timingType = .businessDayOfPeriod
            dayValue = day
        case .daysBeforeEnd(let days):
            timingType = .daysBeforeEnd
            dayValue = days
        }
        selectedHour = rule.hour
        selectedMinute = rule.minute
    }

    private func syncToRule() {
        let timing: PeriodicReminderRule.Timing
        switch timingType {
        case .dayOfPeriod:
            timing = .dayOfPeriod(dayValue)
        case .businessDayOfPeriod:
            timing = .businessDayOfPeriod(dayValue)
        case .daysBeforeEnd:
            timing = .daysBeforeEnd(dayValue)
        }
        rule = PeriodicReminderRule(timing: timing, hour: selectedHour, minute: selectedMinute)
    }
}
