import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileDurationPickerSheet: View {
    let title: String
    let initialMinutes: Int
    let onSave: (Int) -> Void
    let onDismiss: () -> Void

    @State private var selectedMinutes: Int

    init(
        title: String,
        initialMinutes: Int,
        onSave: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.initialMinutes = NotificationSettings.normalizedSnoozeMinutes(initialMinutes)
        self.onSave = onSave
        self.onDismiss = onDismiss
        _selectedMinutes = State(initialValue: NotificationSettings.normalizedSnoozeMinutes(initialMinutes))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProfileMinuteWheel(
                    selection: $selectedMinutes,
                    minuteInterval: 5
                )
                .frame(maxWidth: .infinity)
                .frame(height: ProfileDurationPickerMetrics.pickerHeight)
                .clipped()
                .padding(.bottom, ProfileDurationPickerMetrics.contentSpacing)

                HStack {
                    Button {
                        HomeInteractionFeedback.completion()
                        onSave(selectedMinutes)
                    } label: {
                        HStack {
                            Spacer(minLength: 0)
                            Text("保存")
                                .font(AppTheme.typography.sized(17, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.title)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ProfileDurationPickerMetrics.buttonHeight)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: ProfileDurationPickerMetrics.buttonCornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(ProfileDurationActionButtonStyle())
                    .modifier(ProfileDurationGlassModifier())
                }
                .padding(.horizontal, ProfileDurationPickerMetrics.horizontalInset)
                .padding(.bottom, ProfileDurationPickerMetrics.verticalInset)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        HomeInteractionFeedback.selection()
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selectedMinutes)
    }
}

private struct ProfileMinuteWheel: View {
    @Binding var selection: Int
    let minuteInterval: Int

    var body: some View {
        ZStack {
            ProfileMinuteWheelRepresentable(
                selection: $selection,
                minuteInterval: minuteInterval
            )
            .mask(ProfileDurationWheelFadeMask())

            ProfileMinuteSelectionCapsule(selection: selection)
                .padding(.horizontal, ProfileDurationPickerMetrics.horizontalInset)
                .allowsHitTesting(false)
        }
    }
}

private struct ProfileMinuteSelectionCapsule: View {
    let selection: Int

    private var minuteText: String {
        if selection >= 60, selection.isMultiple(of: 60) {
            return "\(selection / 60) 小时"
        }
        return "\(selection) 分钟"
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.82))

                Text(minuteText)
                    .contentTransition(.numericText())
                    .font(AppTheme.typography.sized(31, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
            }
            .offset(x: -3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ProfileDurationPickerMetrics.selectionCapsuleHeight)
        .background(
            RoundedRectangle(
                cornerRadius: ProfileDurationPickerMetrics.selectionCapsuleHeight * 0.5,
                style: .continuous
            )
            .fill(AppTheme.colors.pillSurface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ProfileDurationPickerMetrics.selectionCapsuleHeight * 0.5,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: AppTheme.colors.shadow.opacity(0.12), radius: 16, y: 5)
        .animation(.easeInOut(duration: 0.22), value: minuteText)
    }
}

private struct ProfileMinuteWheelRepresentable: UIViewRepresentable {
    @Binding var selection: Int
    let minuteInterval: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ProfileMinuteWheelTableView {
        let tableView = ProfileMinuteWheelTableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.decelerationRate = .normal
        tableView.rowHeight = ProfileDurationPickerMetrics.rowHeight
        tableView.register(
            ProfileMinuteWheelCell.self,
            forCellReuseIdentifier: ProfileMinuteWheelCell.reuseIdentifier
        )
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

    func updateUIView(_ uiView: ProfileMinuteWheelTableView, context: Context) {
        let roundedSelection = Self.rounded(selection, minuteInterval: minuteInterval)
        if selection != roundedSelection {
            DispatchQueue.main.async {
                selection = roundedSelection
            }
        }
        context.coordinator.parent = self
        context.coordinator.syncSelectionIfNeeded(in: uiView, targetValue: roundedSelection)
        context.coordinator.updateVisibleCells(in: uiView)
    }

    private static func rounded(_ value: Int, minuteInterval: Int) -> Int {
        let roundedMinute = Int((Double(value) / Double(minuteInterval)).rounded()) * minuteInterval
        return min(max(roundedMinute, 5), 180)
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate {
        var parent: ProfileMinuteWheelRepresentable
        private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        private var lastCenteredRow: Int?
        private var isProgrammaticScroll = false

        init(_ parent: ProfileMinuteWheelRepresentable) {
            self.parent = parent
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            slotCount * ProfileDurationPickerMetrics.loopMultiplier
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ProfileMinuteWheelCell.reuseIdentifier,
                for: indexPath
            ) as? ProfileMinuteWheelCell ?? ProfileMinuteWheelCell(
                style: .default,
                reuseIdentifier: ProfileMinuteWheelCell.reuseIdentifier
            )
            cell.configure(text: minuteLabel(for: minuteValue(for: indexPath.row)))
            return cell
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            guard let cell = cell as? ProfileMinuteWheelCell else { return }
            applyAppearance(to: cell, in: tableView)
        }

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? ProfileMinuteWheelTableView else { return }
            let inset = max((tableView.bounds.height - ProfileDurationPickerMetrics.rowHeight) * 0.5, 0)
            if abs(tableView.contentInset.top - inset) > 0.5 || abs(tableView.contentInset.bottom - inset) > 0.5 {
                tableView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
                tableView.scrollIndicatorInsets = tableView.contentInset
                if let lastCenteredRow {
                    tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: lastCenteredRow, in: tableView)), animated: false)
                } else {
                    configureInitialSelection(for: tableView)
                }
            }
            updateVisibleCells(in: tableView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? ProfileMinuteWheelTableView else { return }
            let centeredRow = nearestRow(in: tableView)
            if centeredRow != lastCenteredRow {
                lastCenteredRow = centeredRow
                let centeredValue = minuteValue(for: centeredRow)
                if parent.selection != centeredValue {
                    parent.selection = centeredValue
                    if !isProgrammaticScroll {
                        selectionFeedbackGenerator.selectionChanged()
                    }
                }
            }
            updateVisibleCells(in: tableView)
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard let tableView = scrollView as? ProfileMinuteWheelTableView else { return }
            let targetRow = nearestRow(for: targetContentOffset.pointee.y, in: tableView)
            targetContentOffset.pointee.y = offsetY(forRow: targetRow, in: tableView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let tableView = scrollView as? ProfileMinuteWheelTableView else { return }
            snapToNearestRow(in: tableView, animated: true)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let tableView = scrollView as? ProfileMinuteWheelTableView else { return }
            snapToNearestRow(in: tableView, animated: true)
        }

        func configureInitialSelection(for tableView: ProfileMinuteWheelTableView) {
            let row = targetRow(for: parent.selection)
            lastCenteredRow = row
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: row, in: tableView)), animated: false)
            updateVisibleCells(in: tableView)
        }

        func syncSelectionIfNeeded(in tableView: ProfileMinuteWheelTableView, targetValue: Int) {
            guard tableView.bounds.height > 0 else { return }
            let centeredRow = nearestRow(in: tableView)
            let targetRow = targetRow(for: targetValue, preferredRow: centeredRow)
            guard targetRow != centeredRow else { return }
            isProgrammaticScroll = true
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: targetRow, in: tableView)), animated: true)
            isProgrammaticScroll = false
        }

        func updateVisibleCells(in tableView: UITableView) {
            for case let cell as ProfileMinuteWheelCell in tableView.visibleCells {
                applyAppearance(to: cell, in: tableView)
            }
        }

        private func applyAppearance(to cell: ProfileMinuteWheelCell, in tableView: UITableView) {
            let visibleCenterY = tableView.contentOffset.y + tableView.bounds.height * 0.5
            let distance = abs(cell.center.y - visibleCenterY)
            let normalized = min(distance / ProfileDurationPickerMetrics.rowHeight, 5)
            let isCentered = distance < (ProfileDurationPickerMetrics.rowHeight * 0.5)
            let alpha = isCentered ? 0.008 : max(0.04, 0.58 - normalized * 0.13)
            let scale = isCentered ? 1 : max(0.84, 1 - normalized * 0.04)
            cell.applyAppearance(alpha: alpha, scale: scale, isCentered: isCentered)
        }

        private var slotCount: Int {
            Int(((180 - 5) / parent.minuteInterval) + 1)
        }

        private func minuteValue(for row: Int) -> Int {
            let slotIndex = ((row % slotCount) + slotCount) % slotCount
            return 5 + (slotIndex * parent.minuteInterval)
        }

        private func minuteLabel(for minutes: Int) -> String {
            if minutes >= 60, minutes.isMultiple(of: 60) {
                return "\(minutes / 60) 小时"
            }
            return "\(minutes) 分钟"
        }

        private func snapToNearestRow(in tableView: ProfileMinuteWheelTableView, animated: Bool) {
            let row = nearestRow(in: tableView)
            recenterIfNeeded(tableView, around: row)
            isProgrammaticScroll = true
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: row, in: tableView)), animated: animated)
            isProgrammaticScroll = false
            lastCenteredRow = row
            let centeredValue = minuteValue(for: row)
            if parent.selection != centeredValue {
                parent.selection = centeredValue
            }
        }

        private func nearestRow(in tableView: UITableView) -> Int {
            nearestRow(for: tableView.contentOffset.y, in: tableView)
        }

        private func nearestRow(for offsetY: CGFloat, in tableView: UITableView) -> Int {
            let raw = Int(round((offsetY + tableView.contentInset.top) / ProfileDurationPickerMetrics.rowHeight))
            return min(max(raw, 0), max(tableView.numberOfRows(inSection: 0) - 1, 0))
        }

        private func offsetY(forRow row: Int, in tableView: UITableView) -> CGFloat {
            (CGFloat(row) * ProfileDurationPickerMetrics.rowHeight) - tableView.contentInset.top
        }

        private func targetRow(for value: Int, preferredRow: Int? = nil) -> Int {
            let slotIndex = max((value - 5) / parent.minuteInterval, 0)
            let middleCycle = ProfileDurationPickerMetrics.loopMultiplier / 2
            let base = slotIndex + middleCycle * slotCount

            guard let preferredRow else { return base }
            return [base - slotCount, base, base + slotCount]
                .min(by: { abs($0 - preferredRow) < abs($1 - preferredRow) }) ?? base
        }

        private func recenterIfNeeded(_ tableView: ProfileMinuteWheelTableView, around row: Int) {
            let cycle = row / slotCount
            let middleCycle = ProfileDurationPickerMetrics.loopMultiplier / 2
            guard abs(cycle - middleCycle) > 20 else { return }
            let centeredRow = (row % slotCount) + middleCycle * slotCount
            tableView.setContentOffset(CGPoint(x: 0, y: offsetY(forRow: centeredRow, in: tableView)), animated: false)
            lastCenteredRow = centeredRow
        }
    }
}

private struct ProfileDurationWheelFadeMask: View {
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

private struct ProfileDurationGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: ProfileDurationPickerMetrics.buttonCornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: ProfileDurationPickerMetrics.buttonCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ProfileDurationPickerMetrics.buttonCornerRadius,
                        style: .continuous
                    )
                    .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private struct ProfileDurationActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private enum ProfileDurationPickerMetrics {
    static let horizontalInset: CGFloat = 18
    static let verticalInset: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let pickerHeight: CGFloat = 214
    static let buttonHeight: CGFloat = 66
    static let buttonCornerRadius: CGFloat = 26
    static let loopMultiplier = 200
    static let rowHeight: CGFloat = 34
    static let baseFontSize: CGFloat = 19
    static let selectedFontSize: CGFloat = 24
    static let selectionCapsuleHeight: CGFloat = 62
}

final class ProfileMinuteWheelTableView: UITableView {}

final class ProfileMinuteWheelCell: UITableViewCell {
    static let reuseIdentifier = "ProfileMinuteWheelCell"

    private let minuteLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        minuteLabel.translatesAutoresizingMaskIntoConstraints = false
        minuteLabel.textAlignment = .center
        minuteLabel.adjustsFontSizeToFitWidth = false
        minuteLabel.backgroundColor = .clear
        contentView.addSubview(minuteLabel)

        NSLayoutConstraint.activate([
            minuteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            minuteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            minuteLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            minuteLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        minuteLabel.text = text
    }

    func applyAppearance(alpha: CGFloat, scale: CGFloat, isCentered: Bool) {
        minuteLabel.alpha = alpha
        minuteLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
        minuteLabel.font = AppTheme.typography.sizedUIFont(
            isCentered ? ProfileDurationPickerMetrics.selectedFontSize : ProfileDurationPickerMetrics.baseFontSize,
            weight: isCentered ? .bold : .semibold
        )
        minuteLabel.textColor = UIColor(isCentered ? AppTheme.colors.title : AppTheme.colors.body)
    }
}
