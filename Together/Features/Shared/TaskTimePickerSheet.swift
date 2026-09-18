import SwiftUI
import UIKit
import CoreText

/// A shared time surface. Callers adapt its local preview to their own editor draft.
struct TaskTimePickerSheet: View {
    let selectionFeedback: () -> Void
    let onChange: (ExistingTaskScheduleDraft) -> Void
    private let scale: TaskTimeRulerScale
    private let contextTitle: String?
    private let onContentHeightChange: ((CGFloat) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .caption) private var labelSize = 13.0
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 46.0
    @Namespace private var rulerViewport
    @State private var draft: ExistingTaskScheduleDraft
    @State private var publishedDraft: ExistingTaskScheduleDraft
    @State private var scrollID: Int?
    @State private var visibleIndex: Int
    @State private var acceptsScrollSelection = false
    @State private var isRulerTouched = false
    @State private var lightResetID = 0
    @State private var showsSystemPicker = false
    @State private var lastFeedbackTime: TimeInterval = 0
    @State private var contentHeight: CGFloat = 208
    @State private var rulerFeedback = UISelectionFeedbackGenerator()

    init(
        presentation: ExistingTaskScheduleEditorPresentation,
        selectionFeedback: @escaping () -> Void,
        onChange: @escaping (ExistingTaskScheduleDraft) -> Void
    ) {
        self.init(
            initialDraft: presentation.initialDraft,
            selectionFeedback: selectionFeedback,
            onChange: onChange
        )
    }

    init(
        initialDraft: ExistingTaskScheduleDraft,
        contextTitle: String? = nil,
        calendar: Calendar = .current,
        seed: Date = .now,
        onContentHeightChange: ((CGFloat) -> Void)? = nil,
        selectionFeedback: @escaping () -> Void,
        onChange: @escaping (ExistingTaskScheduleDraft) -> Void
    ) {
        self.selectionFeedback = selectionFeedback
        self.onChange = onChange
        self.contextTitle = contextTitle
        self.onContentHeightChange = onContentHeightChange
        let draft = initialDraft
        let scale = TaskTimeRulerScale(
            on: draft.selectedDate,
            minuteInterval: ExistingTaskScheduleEditorPolicy.timeMinuteInterval,
            calendar: calendar
        )
        self.scale = scale
        let index = scale.nearestIndex(to: draft.selectedTime ?? seed)
        _draft = State(initialValue: draft)
        _publishedDraft = State(initialValue: draft)
        _scrollID = State(initialValue: index)
        _visibleIndex = State(initialValue: index)
    }

    var body: some View {
        GeometryReader { geometry in
            // The system detent adds the bottom safe area. Count it once, and use
            // the same visible inset on the other edges without entering it.
            let inset = max(24, geometry.safeAreaInsets.bottom)
            ScrollView {
                VStack(spacing: 12) {
                    ruler
                    footer(availableWidth: max(0, geometry.size.width - inset * 2))
                }
                .padding(.horizontal, inset)
                .padding(.top, inset)
                .padding(.bottom, max(0, inset - geometry.safeAreaInsets.bottom))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                    onContentHeightChange?($0)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppTheme.colors.surface)
        .presentationBackground(AppTheme.colors.surface)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.hidden)
        .accessibilityAction(.escape) { dismiss() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetRulerLight() }
        }
        .onDisappear {
            resetRulerLight()
            publishChange()
        }
    }

    private var tickSpacing: CGFloat { 20 }
    private var rulerHeight: CGFloat { labelSize + 64 }
    private var labelInterval: Int { dynamicTypeSize >= .xxLarge ? 30 : 15 }

    private var ruler: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(scale.times.indices, id: \.self) { index in
                        tick(at: index, viewportWidth: width)
                            .id(index)
                            .onGeometryChange(for: Bool.self) { cell in
                                let center = cell.frame(in: .named(rulerViewport)).midX
                                return center >= width / 2 - tickSpacing / 2
                                    && center < width / 2 + tickSpacing / 2
                            } action: { isCentered in
                                guard isCentered else { return }
                                visibleIndex = index
                                guard acceptsScrollSelection, !showsSystemPicker else { return }
                                previewTime(at: index)
                                selectionFeedbackIfNeeded()
                            }
                    }
                }
                .scrollTargetLayout()
                // Real content padding participates in the initial target layout.
                // contentMargins can arrive after scrollPosition's first placement.
                .padding(.horizontal, max(0, (width - tickSpacing) / 2))
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never, anchor: .center))
            .scrollPosition(id: $scrollID, anchor: .center)
            .onScrollPhaseChange { _, phase in
                // Tracking begins with finger-down, before the selected time changes.
                // Deceleration keeps selecting normally but does not ignite new marks.
                isRulerTouched = (phase == .tracking || phase == .interacting)
                    && !showsSystemPicker && scenePhase == .active
                if phase == .interacting {
                    acceptsScrollSelection = true
                    rulerFeedback.prepare()
                } else if phase == .idle {
                    if acceptsScrollSelection {
                        previewTime(at: visibleIndex)
                        publishChange()
                    }
                    acceptsScrollSelection = false
                }
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.14),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    let offset = Int(((value.location.x - width / 2) / tickSpacing).rounded())
                    selectTime(at: scale.clampedIndex(visibleIndex + offset))
                }
            )
            .overlay(alignment: .bottom) {
                Image(systemName: draft.hasExplicitTime ? "triangle.fill" : "triangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("时间刻度")
            .accessibilityValue(timeAccessibilityValue)
            .accessibilityHint("上下轻扫以五分钟调整，或轻点下方时间使用系统选择器")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: selectTime(at: scale.clampedIndex(visibleIndex + 1))
                case .decrement: selectTime(at: scale.clampedIndex(visibleIndex - 1))
                @unknown default: break
                }
            }
        }
        .coordinateSpace(name: rulerViewport)
        .frame(height: rulerHeight)
    }

    private func tick(at index: Int, viewportWidth: CGFloat) -> some View {
        let minimumOpacity = contrast == .increased ? 0.55 : 0.24
        let viewportSpace = rulerViewport
        let edgeBlur = reduceTransparency || contrast == .increased ? 0.0 : 3.5
        return VStack(spacing: 0) {
            Color.clear.frame(height: labelSize + 10)
            ZStack {
                rulerMark(viewportWidth: viewportWidth)
                if index < scale.times.count - 1 {
                    // All marks have the same geometry; only 5-minute nodes snap.
                    rulerMark(viewportWidth: viewportWidth)
                        .offset(x: tickSpacing / 2)
                }
            }
            .frame(width: tickSpacing, height: 34)
        }
        .frame(width: tickSpacing, height: rulerHeight, alignment: .top)
        .overlay(alignment: .top) {
            if scale.showsLabel(at: index, every: labelInterval) {
                Text(verbatim: scale.label(at: index))
                    .font(.system(size: labelSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.colors.title)
                    .fixedSize()
                    .visualEffect { content, geometry in
                        let distance = abs(geometry.frame(in: .named(viewportSpace)).midX - viewportWidth / 2)
                        let proximity = max(0, 1 - distance / (viewportWidth * 0.42))
                        let edge = min(1, max(0, (distance - viewportWidth * 0.32) / (viewportWidth * 0.18)))
                        return content
                            .opacity(minimumOpacity + (1 - minimumOpacity) * proximity)
                            .blur(radius: edge * edge * edgeBlur)
                    }
            }
        }
    }

    private func rulerMark(viewportWidth: CGFloat) -> some View {
        TaskTimeRulerMark(
            ink: AppTheme.colors.title,
            viewport: rulerViewport,
            viewportWidth: viewportWidth,
            pitch: tickSpacing / 2,
            isTouching: isRulerTouched,
            resetID: lightResetID
        )
    }

    @ViewBuilder
    private func footer(availableWidth: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                timeReadout(availableWidth: availableWidth)
                clearButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    timeReadout(availableWidth: availableWidth).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    clearButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    timeReadout(availableWidth: availableWidth)
                    clearButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func timeReadout(availableWidth: CGFloat) -> some View {
        let metrics = TaskTimeReadoutMetrics(size: timeSize, maximumWidth: max(44, availableWidth - 16))
        return VStack(alignment: .leading, spacing: 12) {
            Text(dateTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                acceptsScrollSelection = false
                resetRulerLight()
                publishChange()
                showsSystemPicker = true
            } label: {
                Text(verbatim: draft.selectedTime.map(scale.label(for:)) ?? "--:--")
                    .font(Font(metrics.font))
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: draft.selectedTime?.timeIntervalSinceReferenceDate ?? 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: draft.selectedTime)
                    .foregroundStyle(AppTheme.colors.title)
                    // Trim the font's invisible ascent/descent, keeping native Text
                    // and its digit transition. A stable 00:00 sample avoids jitter.
                    .padding(metrics.opticalInsets)
                    .frame(minHeight: 44, alignment: .bottomLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("使用系统时间选择器")
            .accessibilityValue(timeAccessibilityValue)
            .popover(isPresented: $showsSystemPicker) {
                TaskTimeSystemPicker(
                    selection: systemTimeSelection,
                    minimumDate: scale.times.first!,
                    maximumDate: scale.times.last!,
                    calendar: scale.calendar
                )
                .frame(width: 280, height: 200)
                .padding(12)
                .presentationCompactAdaptation(.popover)
            }
        }
        .containerCornerOffset([.leading, .bottom], sizeToFit: true)
    }

    private var clearButton: some View {
        Button("清除时间") {
            acceptsScrollSelection = false
            resetRulerLight()
            selectionFeedback()
            draft.setTimeEnabled(false)
            publishChange()
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(draft.hasExplicitTime ? AppTheme.colors.body : AppTheme.colors.textTertiary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(
            AppTheme.colors.pillSurface,
            in: ConcentricRectangle(corners: .concentric(minimum: .fixed(16)), isUniform: true)
        )
        .buttonStyle(.plain)
        .disabled(!draft.hasExplicitTime)
        .accessibilityHint("保留日期，同时清除提醒")
    }

    private var dateTitle: String {
        if let contextTitle { return contextTitle }
        if Calendar.current.isDateInToday(draft.selectedDate) { return "今天" }
        if Calendar.current.isDateInTomorrow(draft.selectedDate) { return "明天" }
        return draft.selectedDate.formatted(.dateTime.month().day().weekday())
    }

    private var timeAccessibilityValue: String {
        draft.selectedTime.map(scale.label(for:)) ?? "未设置时间"
    }

    private var systemTimeSelection: Binding<Date> {
        Binding(
            get: { draft.selectedTime ?? scale.times[visibleIndex] },
            set: { time in selectTime(at: scale.nearestIndex(to: time)) }
        )
    }

    private func previewTime(at index: Int) {
        let time = scale.times[index]
        guard draft.selectedTime != time else { return }
        draft.selectTime(time, calendar: scale.calendar)
    }

    private func selectTime(at index: Int) {
        acceptsScrollSelection = false
        resetRulerLight()
        visibleIndex = index
        previewTime(at: index)
        selectionFeedback()
        publishChange()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            scrollID = index
        }
    }

    private func selectionFeedbackIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFeedbackTime >= 0.09 else { return }
        lastFeedbackTime = now
        rulerFeedback.selectionChanged()
    }

    private func resetRulerLight() {
        isRulerTouched = false
        lightResetID &+= 1
    }

    private func publishChange() {
        guard draft != publishedDraft else { return }
        publishedDraft = draft
        onChange(draft)
    }
}

/// Stable optical bounds for the native numeric Text, without a second background
/// or clipping its rolling digits to a rounded rectangle.
private struct TaskTimeReadoutMetrics {
    let font: UIFont
    let opticalInsets: EdgeInsets

    init(size: CGFloat, maximumWidth: CGFloat) {
        let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .light)
        let preferred = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size)
        let preferredSample = NSAttributedString(string: "00:00", attributes: [.font: preferred])
        let preferredWidth = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(preferredSample), nil, nil, nil)
        // Fit the complete time even at the largest accessibility sizes. Measure
        // optical bounds after fitting, so shrinking cannot undo the alignment.
        font = preferred.withSize(size * min(1, maximumWidth / max(1, preferredWidth)))
        let sample = NSAttributedString(string: "00:00", attributes: [.font: font])
        let bounds = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(sample), .useGlyphPathBounds)
        opticalInsets = EdgeInsets(
            top: -max(0, font.ascender - bounds.maxY),
            leading: -max(0, bounds.minX),
            bottom: -max(0, -font.descender + bounds.minY),
            trailing: 0
        )
    }
}

/// Native precision entry. Programmatic setup never emits a selection change.
private struct TaskTimeSystemPicker: UIViewRepresentable {
    @Binding var selection: Date
    let minimumDate: Date
    let maximumDate: Date
    let calendar: Calendar

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.calendar = calendar
        picker.timeZone = calendar.timeZone
        picker.minuteInterval = ExistingTaskScheduleEditorPolicy.timeMinuteInterval
        picker.minimumDate = minimumDate
        picker.maximumDate = maximumDate
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        picker.setDate(selection, animated: false)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.selection = $selection
        if picker.date != selection { picker.setDate(selection, animated: false) }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func changed(_ picker: UIDatePicker) { selection.wrappedValue = picker.date }
    }
}
