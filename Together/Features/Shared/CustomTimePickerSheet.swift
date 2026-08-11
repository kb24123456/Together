import SwiftUI

struct CustomTimePickerSheet: View {
    @Binding var selection: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var centeredSlot: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var lastFeedbackSlot: Int?

    init(selection: Binding<Date>) {
        _selection = selection
        _centeredSlot = State(initialValue: CustomTimePickerScale.slot(for: selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: CustomTimePickerMetrics.topSpacing)

            VStack(spacing: AppTheme.spacing.md) {
                Text("开始时间")
                    .font(.headline)
                    .foregroundStyle(AppTheme.colors.body)

                Text(verbatim: timeText)
                    .font(AppTheme.typography.sized(CustomTimePickerMetrics.timeFontSize, weight: .bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .contentTransition(.numericText())
                    .accessibilityLabel("开始时间")
                    .accessibilityValue(accessibilityTimeText)
            }
            .padding(.horizontal, AppTheme.spacing.xl)

            Spacer(minLength: CustomTimePickerMetrics.scaleTopSpacing)

            timeScale
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.bottom, CustomTimePickerMetrics.bottomSpacing)
        }
        .background(AppTheme.colors.surface)
        .onChange(of: selection) { _, newValue in
            guard isDragging == false else { return }
            centeredSlot = CustomTimePickerScale.slot(for: newValue)
        }
        .presentationDetents([.height(CustomTimePickerMetrics.preferredHeight)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(AppTheme.radius.xxl)
        .presentationBackground(AppTheme.colors.surface)
    }

    private var timeScale: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let centerX = size.width * 0.5
                    let visibleRadius = Int(ceil(size.width / CustomTimePickerMetrics.tickSpacing * 0.5)) + 2

                    for relativeSlot in -visibleRadius...visibleRadius {
                        let slot = CustomTimePickerScale.wrappedSlot(centeredSlot + relativeSlot)
                        let x = centerX
                            + CGFloat(relativeSlot) * CustomTimePickerMetrics.tickSpacing
                            + dragOffset
                        guard x >= -CustomTimePickerMetrics.tickSpacing,
                              x <= size.width + CustomTimePickerMetrics.tickSpacing
                        else { continue }

                        let tickHeight = CustomTimePickerScale.tickHeight(for: slot)
                        let rect = CGRect(
                            x: x - CustomTimePickerMetrics.tickWidth * 0.5,
                            y: size.height - tickHeight,
                            width: CustomTimePickerMetrics.tickWidth,
                            height: tickHeight
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: CustomTimePickerMetrics.tickWidth * 0.5),
                            with: .color(AppTheme.colors.body.opacity(tickHeight > 12 ? 0.24 : 0.13))
                        )
                    }
                }

                VStack {
                    Spacer()
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.coral)
                        .frame(
                            width: CustomTimePickerMetrics.indicatorWidth,
                            height: CustomTimePickerMetrics.indicatorHeight
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(scaleGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("时间刻度")
            .accessibilityValue(accessibilityTimeText)
            .accessibilityHint("左右拖动，以 5 分钟为单位调整")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    moveByAccessibilityStep(1)
                case .decrement:
                    moveByAccessibilityStep(-1)
                @unknown default:
                    break
                }
            }
        }
        .frame(height: CustomTimePickerMetrics.scaleHeight)
    }

    private var scaleGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width

                let stepDelta = Int(
                    (-value.translation.width / CustomTimePickerMetrics.tickSpacing).rounded()
                )
                let liveSlot = CustomTimePickerScale.wrappedSlot(centeredSlot + stepDelta)
                guard liveSlot != lastFeedbackSlot else { return }
                lastFeedbackSlot = liveSlot
                updateSelection(to: liveSlot)
                HomeInteractionFeedback.selection()
            }
            .onEnded { value in
                let stepDelta = CustomTimePickerScale.projectedStepDelta(
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width,
                    tickSpacing: CustomTimePickerMetrics.tickSpacing
                )
                let targetSlot = CustomTimePickerScale.wrappedSlot(centeredSlot + stepDelta)
                let continuityOffset = value.translation.width
                    + CGFloat(stepDelta) * CustomTimePickerMetrics.tickSpacing

                centeredSlot = targetSlot
                dragOffset = continuityOffset
                isDragging = false
                lastFeedbackSlot = nil
                updateSelection(to: targetSlot)

                if reduceMotion {
                    dragOffset = 0
                } else {
                    withAnimation(.spring(duration: 0.30, bounce: 0.08)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var timeText: String {
        selection.formatted(date: .omitted, time: .shortened)
    }

    private var accessibilityTimeText: String {
        selection.formatted(.dateTime.hour().minute())
    }

    private func moveByAccessibilityStep(_ delta: Int) {
        centeredSlot = CustomTimePickerScale.wrappedSlot(centeredSlot + delta)
        updateSelection(to: centeredSlot)
        HomeInteractionFeedback.selection()
    }

    private func updateSelection(to slot: Int) {
        selection = CustomTimePickerScale.date(for: slot, on: selection)
    }
}

enum CustomTimePickerScale {
    nonisolated static let minuteInterval = 5
    nonisolated static let slotCount = 24 * 60 / minuteInterval
    nonisolated static let maximumProjectedStepDelta = 24

    nonisolated static func slot(for date: Date, calendar: Calendar = .current) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let rawSlot = Int((Double(hour * 60 + minute) / Double(minuteInterval)).rounded())
        return wrappedSlot(rawSlot)
    }

    nonisolated static func wrappedSlot(_ slot: Int) -> Int {
        let remainder = slot % slotCount
        return remainder >= 0 ? remainder : remainder + slotCount
    }

    nonisolated static func date(
        for slot: Int,
        on date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let totalMinutes = wrappedSlot(slot) * minuteInterval
        return calendar.date(
            bySettingHour: totalMinutes / 60,
            minute: totalMinutes % 60,
            second: 0,
            of: date
        ) ?? date
    }

    nonisolated static func projectedStepDelta(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        tickSpacing: CGFloat
    ) -> Int {
        guard tickSpacing > 0 else { return 0 }
        let projected = abs(predictedTranslation) > abs(translation)
            ? predictedTranslation
            : translation
        let rawDelta = Int((-projected / tickSpacing).rounded())
        return min(max(rawDelta, -maximumProjectedStepDelta), maximumProjectedStepDelta)
    }

    nonisolated static func tickHeight(for slot: Int) -> CGFloat {
        let minute = wrappedSlot(slot) * minuteInterval
        if minute.isMultiple(of: 60) { return 30 }
        if minute.isMultiple(of: 30) { return 22 }
        if minute.isMultiple(of: 15) { return 15 }
        return 6
    }
}

private enum CustomTimePickerMetrics {
    static let preferredHeight: CGFloat = 520
    static let topSpacing: CGFloat = 72
    static let scaleTopSpacing: CGFloat = 72
    static let bottomSpacing: CGFloat = 34
    static let timeFontSize: CGFloat = 86
    static let scaleHeight: CGFloat = 82
    static let tickSpacing: CGFloat = 14
    static let tickWidth: CGFloat = 3
    static let indicatorWidth: CGFloat = 5
    static let indicatorHeight: CGFloat = 42
}

#Preview("Custom Time Picker Sheet") {
    CustomTimePickerPreviewHost()
}

private struct CustomTimePickerPreviewHost: View {
    @State private var selection = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 11, hour: 8, minute: 55)
    ) ?? .now

    var body: some View {
        CustomTimePickerSheet(selection: $selection)
    }
}
