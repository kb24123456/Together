import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RoutinesReminderRulePicker: View {
    @Binding var rule: PeriodicReminderRule
    let cycle: PeriodicCycle
    var onDelete: (() -> Void)?

    @State private var dayMode: DayMode = .beforeEnd
    @State private var dayType: DayType = .natural
    @State private var dayValue: Int = 3

    enum DayMode: String, CaseIterable {
        case absoluteDay
        case beforeEnd

        var label: String {
            switch self {
            case .absoluteDay: "第几天"
            case .beforeEnd: "截止前几天"
            }
        }
    }

    enum DayType: String, CaseIterable {
        case natural
        case business

        var label: String {
            switch self {
            case .natural: "自然日"
            case .business: "工作日"
            }
        }
    }

    private static let optionRowHeight: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if let onDelete {
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            HomeInteractionFeedback.delete()
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(AppTheme.typography.sized(14, weight: .medium))
                                .foregroundStyle(AppTheme.colors.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, TaskEditorMenuOptionMetrics.outerInset)
                    .padding(.top, AppTheme.spacing.xs)
                    .padding(.bottom, AppTheme.spacing.xxs)
                }

                // Row 1: 自然日 / 工作日 — always visible when supported, disabled in beforeEnd mode
                if supportsBusinessDay {
                    dayTypeRow
                        .padding(.top, AppTheme.spacing.sm)
                        .padding(.horizontal, TaskEditorMenuOptionMetrics.outerInset)
                        .padding(.bottom, AppTheme.spacing.xs)
                        .opacity(dayMode == .beforeEnd ? 0.32 : 1)
                        .allowsHitTesting(dayMode == .absoluteDay)
                }

                // Row 2: 第几天 / 截止前几天
                dayModeRow
                    .padding(.top, supportsBusinessDay ? 0 : AppTheme.spacing.sm)
                    .padding(.horizontal, TaskEditorMenuOptionMetrics.outerInset)
                    .padding(.bottom, AppTheme.spacing.xs)

                // Day number wheel
                PeriodicDayWheelView(
                    value: $dayValue,
                    range: dayValueRange,
                    labelPrefix: wheelLabelPrefix
                )
                .frame(maxWidth: .infinity)
                .frame(height: adaptiveWheelHeight(available: proxy.size.height))
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { loadFromRule() }
        .onChange(of: dayMode) { _, _ in clampDayValue(); syncToRule() }
        .onChange(of: dayType) { _, _ in syncToRule() }
        .onChange(of: dayValue) { _, _ in syncToRule() }
    }

    // MARK: - Option rows

    private var dayTypeRow: some View {
        HStack(spacing: AppTheme.spacing.sm) {
            ForEach(DayType.allCases, id: \.rawValue) { type in
                Button { dayType = type } label: {
                    Text(type.label)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(type == dayType ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Self.optionRowHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                                .fill(AppTheme.colors.pillSurface.opacity(type == dayType ? 1 : 0.5))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous))
                }
                .buttonStyle(TaskEditorMenuOptionButtonStyle())
            }
        }
    }

    private var dayModeRow: some View {
        HStack(spacing: AppTheme.spacing.sm) {
            ForEach(DayMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dayMode = mode
                    }
                } label: {
                    Text(mode.label)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(mode == dayMode ? AppTheme.colors.title : AppTheme.colors.body.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Self.optionRowHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                                .fill(AppTheme.colors.pillSurface.opacity(mode == dayMode ? 1 : 0.5))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous))
                }
                .buttonStyle(TaskEditorMenuOptionButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private var supportsBusinessDay: Bool {
        switch cycle {
        case .monthly, .quarterly: true
        default: false
        }
    }

    private var wheelLabelPrefix: String {
        dayMode == .absoluteDay ? "第" : "截止前"
    }

    private var dayValueRange: ClosedRange<Int> {
        switch dayMode {
        case .absoluteDay:
            if dayType == .business { return 1...20 }
            switch cycle {
            case .weekly: return 1...7
            case .monthly: return 1...31
            case .quarterly: return 1...90
            case .yearly: return 1...365
            }
        case .beforeEnd:
            switch cycle {
            case .weekly: return 1...6
            case .monthly: return 1...30
            case .quarterly: return 1...89
            case .yearly: return 1...364
            }
        }
    }

    private func clampDayValue() {
        let r = dayValueRange
        dayValue = max(r.lowerBound, min(r.upperBound, dayValue))
    }

    private func loadFromRule() {
        switch rule.timing {
        case .dayOfPeriod(let day):
            dayMode = .absoluteDay; dayType = .natural; dayValue = day
        case .businessDayOfPeriod(let day):
            dayMode = .absoluteDay; dayType = .business; dayValue = day
        case .daysBeforeEnd(let days):
            dayMode = .beforeEnd; dayValue = days
        }
    }

    private func syncToRule() {
        let timing: PeriodicReminderRule.Timing
        switch dayMode {
        case .absoluteDay:
            timing = dayType == .business ? .businessDayOfPeriod(dayValue) : .dayOfPeriod(dayValue)
        case .beforeEnd:
            timing = .daysBeforeEnd(dayValue)
        }
        rule = PeriodicReminderRule(timing: timing)
    }

    private func adaptiveWheelHeight(available: CGFloat) -> CGFloat {
        let deleteH: CGFloat = onDelete != nil ? 50 : 0
        let rowH: CGFloat = 10 + Self.optionRowHeight + 6
        let rows: CGFloat = supportsBusinessDay ? 2 : 1
        let used = deleteH + rowH * rows
        return min(max(available - used, TaskEditorTimePickerMetrics.minimumPickerHeight), TaskEditorTimePickerMetrics.pickerHeight)
    }
}

// MARK: - Periodic Day Wheel

private struct PeriodicDayWheelView: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let labelPrefix: String

    private let capsuleHeight: CGFloat = 62
    private let selectionCapsuleFill: Color = AppTheme.colors.pillSurface.opacity(0.96)

    var body: some View {
        ZStack {
            PeriodicDayWheelRepresentable(value: $value, range: range)
                .mask(PeriodicDayWheelFadeMask())

            PeriodicDayWheelSelectionCapsule(
                value: value,
                labelPrefix: labelPrefix,
                capsuleHeight: capsuleHeight,
                fill: selectionCapsuleFill
            )
            .padding(.horizontal, AppTheme.spacing.md)
            .allowsHitTesting(false)
        }
    }
}

private struct PeriodicDayWheelRepresentable: UIViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private static let rowHeight: CGFloat = 34
    private static let loopMultiplier = 100

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TaskEditorSingleColumnTimeTableView {
        let tableView = TaskEditorSingleColumnTimeTableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.decelerationRate = .normal
        tableView.rowHeight = Self.rowHeight
        tableView.register(TaskEditorSingleColumnTimeCell.self, forCellReuseIdentifier: "PeriodicDayCell")
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.configureInitialSelection(for: tableView)
        DispatchQueue.main.async {
            tableView.reloadData()
            tableView.layoutIfNeeded()
            context.coordinator.configureInitialSelection(for: tableView)
        }
        return tableView
    }

    func updateUIView(_ uiView: TaskEditorSingleColumnTimeTableView, context: Context) {
        let oldRange = context.coordinator.parent.range
        context.coordinator.parent = self
        if range != oldRange {
            uiView.reloadData()
            uiView.layoutIfNeeded()
            context.coordinator.configureInitialSelection(for: uiView)
        } else {
            context.coordinator.syncIfNeeded(in: uiView, targetValue: value)
        }
        context.coordinator.updateVisibleCells(in: uiView)
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: PeriodicDayWheelRepresentable
        private let feedback = UISelectionFeedbackGenerator()
        private var lastCenteredRow: Int?
        private var isProgrammatic = false

        init(_ parent: PeriodicDayWheelRepresentable) { self.parent = parent }

        private var count: Int { parent.range.upperBound - parent.range.lowerBound + 1 }
        private var totalRows: Int { count * PeriodicDayWheelRepresentable.loopMultiplier }

        private func value(for row: Int) -> Int {
            let idx = ((row % count) + count) % count
            return parent.range.lowerBound + idx
        }

        private func bestRow(for value: Int, near preferred: Int? = nil) -> Int {
            let clamped = max(parent.range.lowerBound, min(parent.range.upperBound, value))
            let idx = clamped - parent.range.lowerBound
            let mid = PeriodicDayWheelRepresentable.loopMultiplier / 2
            let base = idx + mid * count
            guard let preferred else { return base }
            return [base - count, base, base + count]
                .min(by: { abs($0 - preferred) < abs($1 - preferred) }) ?? base
        }

        // MARK: DataSource

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { totalRows }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "PeriodicDayCell", for: indexPath)
                as? TaskEditorSingleColumnTimeCell
                ?? TaskEditorSingleColumnTimeCell(style: .default, reuseIdentifier: "PeriodicDayCell")
            cell.configure(text: "\(value(for: indexPath.row))")
            return cell
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let cell = cell as? TaskEditorSingleColumnTimeCell else { return }
            applyAppearance(to: cell, in: tableView)
        }

        // MARK: Scroll

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            guard let tv = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            let inset = max((tv.bounds.height - PeriodicDayWheelRepresentable.rowHeight) * 0.5, 0)
            if abs(tv.contentInset.top - inset) > 0.5 {
                tv.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
                tv.scrollIndicatorInsets = tv.contentInset
                if let r = lastCenteredRow {
                    tv.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: r, in: tv)), animated: false)
                } else {
                    configureInitialSelection(for: tv)
                }
            }
            updateVisibleCells(in: tv)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let tv = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            let row = nearestRow(in: tv)
            if row != lastCenteredRow {
                lastCenteredRow = row
                let v = value(for: row)
                if v != parent.value {
                    parent.value = v
                    if !isProgrammatic { feedback.selectionChanged() }
                }
            }
            updateVisibleCells(in: tv)
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            guard let tv = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            let row = nearestRow(for: targetContentOffset.pointee.y, in: tv)
            targetContentOffset.pointee.y = offsetY(forRow: row, in: tv)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let tv = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            snap(in: tv)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let tv = scrollView as? TaskEditorSingleColumnTimeTableView else { return }
            snap(in: tv)
        }

        func configureInitialSelection(for tv: TaskEditorSingleColumnTimeTableView) {
            let row = bestRow(for: parent.value)
            lastCenteredRow = row
            tv.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: row, in: tv)), animated: false)
            updateVisibleCells(in: tv)
        }

        func syncIfNeeded(in tv: TaskEditorSingleColumnTimeTableView, targetValue: Int) {
            guard tv.bounds.height > 0 else { return }
            let curr = nearestRow(in: tv)
            let target = bestRow(for: targetValue, near: curr)
            guard target != curr else { return }
            isProgrammatic = true
            tv.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: target, in: tv)), animated: false)
            isProgrammatic = false
        }

        func updateVisibleCells(in tv: TaskEditorSingleColumnTimeTableView) {
            for case let cell as TaskEditorSingleColumnTimeCell in tv.visibleCells {
                applyAppearance(to: cell, in: tv)
            }
        }

        private func applyAppearance(to cell: TaskEditorSingleColumnTimeCell, in tv: UITableView) {
            let centerY = tv.contentOffset.y + tv.bounds.height * 0.5
            let dist = abs(cell.center.y - centerY)
            let norm = min(dist / PeriodicDayWheelRepresentable.rowHeight, 5)
            let isCentered = dist < PeriodicDayWheelRepresentable.rowHeight * 0.5
            cell.applyAppearance(
                alpha: isCentered ? 0.008 : max(0.04, 0.58 - norm * 0.13),
                scale: isCentered ? 1 : max(0.84, 1 - norm * 0.04),
                isCentered: isCentered
            )
        }

        private func snap(in tv: TaskEditorSingleColumnTimeTableView) {
            let row = nearestRow(in: tv)
            isProgrammatic = true
            tv.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: row, in: tv)), animated: true)
            isProgrammatic = false
            lastCenteredRow = row
            let v = value(for: row)
            if v != parent.value { parent.value = v }
        }

        private func nearestRow(in tv: UITableView) -> Int { nearestRow(for: tv.contentOffset.y, in: tv) }

        private func nearestRow(for offsetY: CGFloat, in tv: UITableView) -> Int {
            let raw = Int(round((offsetY + tv.contentInset.top) / PeriodicDayWheelRepresentable.rowHeight))
            return min(max(raw, 0), max(tv.numberOfRows(inSection: 0) - 1, 0))
        }

        private func offsetY(forRow row: Int, in tv: UITableView) -> CGFloat {
            CGFloat(row) * PeriodicDayWheelRepresentable.rowHeight - tv.contentInset.top
        }
    }
}

private struct PeriodicDayWheelSelectionCapsule: View {
    let value: Int
    let labelPrefix: String
    let capsuleHeight: CGFloat
    let fill: Color

    var body: some View {
        HStack(spacing: 0) {
            Text(labelPrefix)
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.6))

            Text(" \(value) ")
                .contentTransition(.numericText())
                .font(AppTheme.typography.sized(31, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)

            Text("天")
                .font(AppTheme.typography.sized(15, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: capsuleHeight)
        .background(
            RoundedRectangle(cornerRadius: capsuleHeight * 0.5, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: capsuleHeight * 0.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: AppTheme.colors.shadow.opacity(0.12), radius: 16, y: 5)
        .animation(.easeInOut(duration: 0.22), value: value)
        .animation(.easeInOut(duration: 0.22), value: labelPrefix)
    }
}

private struct PeriodicDayWheelFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.55), location: 0.10),
                .init(color: .black.opacity(0.86), location: 0.22),
                .init(color: .black, location: 0.32),
                .init(color: .black, location: 0.68),
                .init(color: .black.opacity(0.86), location: 0.78),
                .init(color: .black.opacity(0.55), location: 0.90),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
