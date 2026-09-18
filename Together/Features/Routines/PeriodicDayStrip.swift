import SwiftUI

/// Discrete dates stay flat. Native scrolling provides inertia and center snapping.
struct PeriodicDayStrip: View {
    let cycle: PeriodicCycle
    let selection: PeriodicReminderRule.Timing?
    let onSelect: (PeriodicReminderRule.Timing) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .title2) private var labelSize = 24.0
    @Namespace private var viewport
    @State private var options: [PeriodicDayPickerOption]
    @State private var scrollPosition: ScrollPosition
    @State private var visibleIndex: Int
    @State private var acceptsScrollSelection = false
    @State private var lastFeedbackTime: TimeInterval = 0

    init(cycle: PeriodicCycle, selection: PeriodicReminderRule.Timing?, onSelect: @escaping (PeriodicReminderRule.Timing) -> Void) {
        self.cycle = cycle
        self.selection = selection
        self.onSelect = onSelect
        let options = PeriodicSchedulePickerValues.days(cycle: cycle, selected: selection)
        let displayed = PeriodicSchedulePickerValues.displayedTiming(selection, cycle: cycle)
        let index = options.firstIndex(where: { $0.timing == displayed }) ?? 0
        _options = State(initialValue: options)
        _visibleIndex = State(initialValue: index)
        _scrollPosition = State(initialValue: ScrollPosition(id: index, anchor: .center))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let space = viewport
            let minimumOpacity = contrast == .increased ? 0.72 : usesSevenDaySlots ? 0.50 : 0.28
            ScrollView(.horizontal) {
                // The finite date set tops out at 91 ordinary choices. Eager
                // layout keeps adaptive slot widths exact when the sheet resizes.
                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { index in
                        Text(verbatim: options[index].label)
                            .font(.system(size: labelSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.colors.title)
                            .fixedSize()
                            .frame(width: cellWidth(at: index, viewportWidth: width), height: labelSize + 28)
                            .contentShape(Rectangle())
                            .onTapGesture { select(index, scroll: true) }
                            .visualEffect { content, proxy in
                                let distance = abs(proxy.frame(in: .named(space)).midX - width / 2)
                                return content.opacity(minimumOpacity + (1 - minimumOpacity) * max(0, 1 - distance / (width * 0.46)))
                            }
                            .id(index)
                            .onGeometryChange(for: Bool.self) { proxy in
                                let frame = proxy.frame(in: .named(space))
                                return abs(frame.midX - width / 2) < frame.width / 2
                            } action: { centered in
                                guard centered else { return }
                                visibleIndex = index
                                if acceptsScrollSelection { select(index, scroll: false) }
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.leading, max(0, (width - cellWidth(at: 0, viewportWidth: width)) / 2))
                .padding(.trailing, max(0, (width - cellWidth(at: options.count - 1, viewportWidth: width)) / 2))
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never, anchor: .center))
            .scrollPosition($scrollPosition, anchor: .center)
            .onChange(of: CGSize(width: width, height: labelSize), initial: true) { _, _ in
                // Preserve the selection when the sheet or Dynamic Type changes
                // the viewport. Reissue even for the same ID; a binding alone
                // can retain its old physical offset after the new padding lands.
                acceptsScrollSelection = false
                let displayed = PeriodicSchedulePickerValues.displayedTiming(selection, cycle: cycle)
                let index = options.firstIndex(where: { $0.timing == displayed }) ?? visibleIndex
                scrollPosition.scrollTo(id: index, anchor: .center)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { acceptsScrollSelection = true }
                if phase == .idle {
                    if acceptsScrollSelection { select(visibleIndex, scroll: false) }
                    acceptsScrollSelection = false
                }
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: usesSevenDaySlots ? 0.02 : 0.12),
                    .init(color: .black, location: usesSevenDaySlots ? 0.98 : 0.88),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
            .overlay(alignment: .bottom) {
                Image(systemName: selection == nil ? "triangle" : "triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: viewport)
        .frame(height: labelSize + 52)
        .onChange(of: selection) { _, value in
            // Opening, clearing and programmatic positioning never commit a date.
            guard let value = PeriodicSchedulePickerValues.displayedTiming(value, cycle: cycle) else {
                acceptsScrollSelection = false
                return
            }
            if !options.contains(where: { $0.timing == value }),
               let option = PeriodicSchedulePickerValues.days(cycle: cycle, selected: value).last {
                options.append(option)
            }
            guard let index = options.firstIndex(where: { $0.timing == value }), index != visibleIndex else { return }
            acceptsScrollSelection = false
            visibleIndex = index
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
                scrollPosition.scrollTo(id: index, anchor: .center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cycle == .weekly ? "星期" : "目标日")
        .accessibilityValue(selection == nil ? "未设置" : options[visibleIndex].title)
        .accessibilityHint("上下轻扫选择，或轻点下方读数快速定位")
        .accessibilityAdjustableAction { direction in
            let index = direction == .increment ? visibleIndex + 1 : visibleIndex - 1
            select(min(max(index, 0), options.count - 1), scroll: true)
        }
    }

    private var usesSevenDaySlots: Bool { cycle == .monthly || cycle == .quarterly }

    private func cellWidth(at index: Int, viewportWidth: CGFloat) -> CGFloat {
        guard options.indices.contains(index) else { return labelSize * 3 }
        let label = options[index].label
        if cycle == .weekly {
            return max(labelSize * 3, CGFloat(label.count) * labelSize + 24)
        }
        // Seven complete numeric slots in ordinary phone widths. At larger
        // text sizes, legibility and 44pt hit regions take priority over count.
        let numericWidth = max(viewportWidth / 7, max(44, labelSize * 1.35 + 10))
        if label.allSatisfy(\.isNumber) { return numericWidth }
        return max(numericWidth, CGFloat(label.count) * labelSize + 8)
    }

    private func select(_ index: Int, scroll: Bool) {
        guard options.indices.contains(index) else { return }
        visibleIndex = index
        if scroll {
            acceptsScrollSelection = false
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
                scrollPosition.scrollTo(id: index, anchor: .center)
            }
        }
        let timing = options[index].timing
        guard PeriodicSchedulePickerValues.displayedTiming(selection, cycle: cycle) != timing else { return }
        onSelect(timing)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFeedbackTime >= 0.09 {
            lastFeedbackTime = now
            HomeInteractionFeedback.selection()
        }
    }
}
