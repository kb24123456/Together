import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeItemDetailSheet: View {
    @Bindable var viewModel: HomeViewModel
    @State private var focusedField: Field?
    @State private var activeMenu: TaskEditorMenu?
    @State private var pendingAction: DetailEntryAction?
    @State private var isAwaitingDeleteConfirmation = false
    @State private var lastFocusedFieldBeforeMenu: Field?
    @State private var focusCoordinator = DetailTextInputFocusCoordinator()
    @StateObject private var keyboardObserver = TaskEditorKeyboardObserver()
    @Namespace private var chipRowNamespace
    @Namespace private var categorySwitcherNamespace

    enum Field: Hashable {
        case title
        case notes
    }

    private enum DetailCategory {
        case task
        case periodic
    }

    private enum DetailEntryAction {
        case none
        case focus(Field)
        case menu(TaskEditorMenu)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.detailDraft != nil {
                    GeometryReader { proxy in
                        Group {
                            if isExpandedEditor {
                                expandedEditorLayout(proxy: proxy)
                            } else {
                                compactDetailLayout(proxy: proxy)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.clear)
        .overlay {
            if activeMenu != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissActiveMenu()
                    }
            }
        }
        .sheet(item: $activeMenu) { menu in
            HomeDetailMenuSheet(menu: menu, viewModel: viewModel, onDismiss: dismissActiveMenu)
                .presentationDetents(menu.detents)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(false)
                .modifier(TaskEditorMenuPresentationSizingModifier())
                .onDisappear {
                    restoreFocusAfterMenuIfNeeded(preferImmediateResponder: true)
                }
        }
        .presentationDetents([.height(340), .large], selection: $viewModel.detailDetent)
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: focusedField) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.markDetailForExpandedEditing()
            }
        }
        .onChange(of: viewModel.detailDetent) { _, newValue in
            guard newValue == .large else { return }
            performPendingActionIfNeeded()
        }
    }

    private var isExpandedEditor: Bool {
        viewModel.detailDetent == .large
    }

    private func compactDetailLayout(proxy: GeometryProxy) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    cancelInlineDeleteConfirmation()
                }

            VStack(alignment: .leading, spacing: 0) {
                compactHeaderSection
                compactMetaSection
                compactChipSection
                    .padding(.top, 14)
                compactActionButtons
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func expandedEditorLayout(proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            expandedCategorySwitcher
                .padding(.top, 18)
                .padding(.bottom, 8)

            expandedEditorSection
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.colors.surface)
        .overlay(alignment: .bottom) {
            expandedBottomActionArea(bottomInset: max(proxy.safeAreaInsets.bottom, 8))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var expandedCategorySwitcher: some View {
        HStack(spacing: 10) {
            ForEach(["周期性", "任务", "项目"], id: \.self) { title in
                let isActive = expandedCategoryTitle == title

                Button {
                    if isActive {
                        HomeInteractionFeedback.selection()
                        focusedField = .title
                    }
                } label: {
                    Text(title)
                        .font(AppTheme.typography.sized(18, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? AppTheme.colors.title : AppTheme.colors.textTertiary)
                        .scaleEffect(isActive ? 1 : 0.96)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 9)
                        .background(
                            ZStack {
                                if isActive {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.colors.surfaceElevated)
                                        .matchedGeometryEffect(
                                            id: "detail.categorySwitcher.selection",
                                            in: categorySwitcherNamespace
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isActive)
            }
        }
        .padding(.bottom, 10)
    }

    private func expandedBottomActionArea(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: viewModel.hasUnsavedDetailChanges ? 12 : 10) {
                Text(currentStateText)
                    .font(AppTheme.typography.sized(15, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.84))

                chipRow { menu in
                    HomeInteractionFeedback.selection()
                    openMenu(menu)
                }

                if viewModel.hasUnsavedDetailChanges {
                    expandedSaveButton
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [.clear, AppTheme.colors.surface.opacity(0.97)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(.bottom, bottomInset)
        .animation(.interpolatingSpring(mass: 1.08, stiffness: 168, damping: 23, initialVelocity: 0.1), value: viewModel.hasUnsavedDetailChanges)
    }

    private var expandedSaveButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            Task {
                await viewModel.saveDetailDraft()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(AppTheme.typography.sized(13, weight: .bold))
                Text("保存")
                    .font(AppTheme.typography.sized(15, weight: .bold))
            }
            .foregroundStyle(AppTheme.colors.title)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
        .padding(.horizontal, 10)
        .modifier(
            TaskEditorPrimaryActionOvershootModifier(
                trigger: viewModel.hasUnsavedDetailChanges,
                keyboardRevealOffset: primaryActionKeyboardRevealOffset
            )
        )
        .transition(.offset(y: 18).combined(with: .opacity))
    }

    private var primaryActionKeyboardRevealOffset: CGFloat {
        guard keyboardObserver.overlap > 0 else { return 0 }
        return min(max(keyboardObserver.overlap * 0.32, 104), 136)
    }

    private var compactHeaderSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.title))
            } label: {
                Text(viewModel.detailDraft?.title ?? "")
                    .font(AppTheme.typography.sized(32, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)

            Button {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.notes))
            } label: {
                Text(compactNotesText)
                    .font(AppTheme.typography.sized(18, weight: .medium))
                    .foregroundStyle(compactNotesColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var compactMetaSection: some View {
        Text(currentStateText)
            .font(AppTheme.typography.sized(15, weight: .semibold))
            .foregroundStyle(AppTheme.colors.body.opacity(0.84))
            .padding(.top, 38)
    }

    private var compactChipSection: some View {
        chipRow { menu in
            HomeInteractionFeedback.selection()
            expandToLarge(for: .menu(menu))
        }
        .opacity(0.94)
    }

    private var compactActionButtons: some View {
        HStack(spacing: 10) {
            compactActionButton(
                title: viewModel.detailDraft?.isPinned == true ? "已置顶" : "置顶",
                systemImage: "pin",
                tint: AppTheme.colors.body
            ) {
                HomeInteractionFeedback.selection()
                viewModel.updateDraftPinned(!(viewModel.detailDraft?.isPinned ?? false))
            }

            compactActionButton(
                title: "编辑",
                systemImage: "pencil",
                tint: AppTheme.colors.body
            ) {
                HomeInteractionFeedback.selection()
                expandToLarge(for: .focus(.title))
            }

            compactDeleteButton
        }
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(AppTheme.typography.sized(22, weight: .semibold))
                Text(title)
                    .font(AppTheme.typography.sized(17, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.72), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var compactDeleteButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            if isAwaitingDeleteConfirmation {
                Task {
                    await viewModel.deleteSelectedItem()
                }
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isAwaitingDeleteConfirmation = true
                }
            }
        } label: {
            ZStack {
                if isAwaitingDeleteConfirmation {
                    compactDeleteContent(
                        title: "确认",
                        systemImage: "checkmark"
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else {
                    compactDeleteContent(
                        title: "移除",
                        systemImage: "trash"
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.colors.pillSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.colors.pillOutline.opacity(0.68), lineWidth: 1)
            }
            .clipped()
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isAwaitingDeleteConfirmation)
        }
        .buttonStyle(.plain)
    }

    private func compactDeleteContent(
        title: String,
        systemImage: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(22, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(AppTheme.typography.sized(17, weight: .semibold))
                .contentTransition(.interpolate)
        }
        .foregroundStyle(AppTheme.colors.coral)
    }

    private var expandedEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailFocusableTextView(
                text: Binding(
                    get: { viewModel.detailDraft?.title ?? "" },
                    set: { viewModel.updateDraftTitle($0) }
                ),
                focusedField: $focusedField,
                focusCoordinator: focusCoordinator,
                field: .title,
                placeholder: detailCategory == .periodic ? "周期任务标题" : "任务标题",
                font: AppTheme.typography.sizedUIFont(30, weight: .bold),
                textColor: UIColor(AppTheme.colors.title),
                placeholderColor: UIColor(AppTheme.colors.textTertiary.opacity(0.62)),
                maximumNumberOfLines: 3
            )

            DetailFocusableTextView(
                text: Binding(
                    get: { viewModel.detailDraft?.notes ?? "" },
                    set: { viewModel.updateDraftNotes($0) }
                ),
                focusedField: $focusedField,
                focusCoordinator: focusCoordinator,
                field: .notes,
                placeholder: "添加备注...",
                font: AppTheme.typography.sizedUIFont(16, weight: .medium),
                textColor: UIColor(AppTheme.colors.body.opacity(0.78)),
                placeholderColor: UIColor(AppTheme.colors.textTertiary.opacity(0.74)),
                maximumNumberOfLines: 8
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func chipRow(action: @escaping (TaskEditorMenu) -> Void) -> some View {
        TaskEditorChipRow(
            chips: chips,
            namespace: chipRowNamespace,
            trailingInset: 0,
            onChipTap: action,
            onClearTap: { chip in
                HomeInteractionFeedback.selection()
                guard chip.menu == .time else { return }
                viewModel.clearDraftDueTime()
            }
        )
    }

    private var detailCategory: DetailCategory {
        viewModel.detailDraft?.repeatRule == nil ? .task : .periodic
    }

    private var expandedCategoryTitle: String {
        switch detailCategory {
        case .periodic:
            return "周期性"
        case .task:
            return "任务"
        }
    }

    private var chips: [TaskEditorRenderedChip] {
        let snapshots: [TaskEditorChipSnapshot]
        switch detailCategory {
        case .task:
            snapshots = [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.date.rawValue,
                    title: taskDateTitle,
                    systemImage: "calendar",
                    menu: .date,
                    semanticValue: .date(viewModel.detailDraft?.dueAt ?? viewModel.selectedDate)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.time.rawValue,
                    title: taskTimeTitle,
                    systemImage: "clock",
                    menu: .time,
                    semanticValue: .time(viewModel.detailDraft?.dueAt),
                    showsTrailingClear: showsTimeClearButton
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.reminder.rawValue,
                    title: reminderTitle,
                    systemImage: "bell",
                    menu: .reminder,
                    semanticValue: .reminder(reminderOffset)
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.priority.rawValue,
                    title: viewModel.detailDraft?.priority.title ?? "普通",
                    systemImage: "flag",
                    menu: .priority,
                    semanticValue: .priority(viewModel.detailDraft?.priority.animationRank ?? 0)
                )
            ]
        case .periodic:
            snapshots = [
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.repeatRule.rawValue,
                    title: repeatTitle,
                    systemImage: "arrow.triangle.2.circlepath",
                    menu: .repeatRule,
                    semanticValue: .repeatRule(
                        title: repeatTitle,
                        rank: viewModel.detailDraft?.repeatRule?.animationRank ?? 0
                    )
                ),
                TaskEditorChipSnapshot(
                    id: TaskEditorMenu.reminder.rawValue,
                    title: reminderTitle,
                    systemImage: "bell",
                    menu: .reminder,
                    semanticValue: .reminder(reminderOffset)
                )
            ]
        }

        return makeRenderedChips(from: snapshots)
    }

    private var taskDateTitle: String {
        localizedRelativeMonthDayText(viewModel.detailDraft?.dueAt ?? viewModel.selectedDate)
    }

    private var taskTimeTitle: String {
        guard
            viewModel.detailDraft?.hasExplicitTime == true,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "时间"
        }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else {
            return remindAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }

        let delta = dueAt.timeIntervalSince(remindAt)
        return TaskEditorReminderPreset.preset(for: delta)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt, calendar: .current)
    }

    private var showsTimeClearButton: Bool {
        viewModel.detailDraft?.hasExplicitTime == true
    }

    private func localizedRelativeMonthDayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func absoluteMonthDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private var compactNotesText: String {
        let notes = viewModel.detailDraft?.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? "添加备注..." : notes
    }

    private var compactNotesColor: Color {
        let notes = viewModel.detailDraft?.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? AppTheme.colors.textTertiary.opacity(0.74) : AppTheme.colors.body.opacity(0.78)
    }

    private var currentStateText: String {
        "\(statusDateText) · \(statusLabelText)"
    }

    private var reminderOffset: TimeInterval? {
        guard
            let dueAt = viewModel.detailDraft?.dueAt,
            let remindAt = viewModel.detailDraft?.remindAt
        else { return nil }
        return dueAt.timeIntervalSince(remindAt)
    }

    private var statusDateText: String {
        if
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        {
            return rule.title(anchorDate: dueAt, calendar: .current)
        }
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "未安排" }
        return localizedRelativeMonthDayText(dueAt)
    }

    private func cancelInlineDeleteConfirmation() {
        guard isAwaitingDeleteConfirmation else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            isAwaitingDeleteConfirmation = false
        }
    }

    private var statusLabelText: String {
        if let item = viewModel.selectedItem,
           item.isCompleted(on: viewModel.selectedDate, calendar: .current) || item.status == .completed {
            return "已完成"
        }
        if let dueAt = viewModel.detailDraft?.dueAt, dueAt <= .now {
            return "已超时"
        }
        return "进行中"
    }

    private func expandToLarge(for action: DetailEntryAction) {
        cancelInlineDeleteConfirmation()
        pendingAction = action

        if isExpandedEditor {
            performPendingActionIfNeeded()
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            viewModel.markDetailForExpandedEditing()
        }
    }

    private func performPendingActionIfNeeded() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .none:
            break
        case let .focus(field):
            DispatchQueue.main.async {
                focusedField = field
            }
        case let .menu(menu):
            openMenu(menu)
        }
    }

    private func restoreFocusAfterMenuIfNeeded(preferImmediateResponder: Bool = false) {
        guard let field = lastFocusedFieldBeforeMenu else { return }
        lastFocusedFieldBeforeMenu = nil
        focusedField = field

        guard preferImmediateResponder else { return }
        focusCoordinator.requestFocus(for: field)
        DispatchQueue.main.async {
            focusCoordinator.requestFocus(for: field)
        }
    }

    private func openMenu(_ menu: TaskEditorMenu) {
        lastFocusedFieldBeforeMenu = focusedField ?? focusCoordinator.currentFocusedField ?? .title
        focusCoordinator.resignCurrentResponder()
        focusedField = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withTransaction(HomeDetailMenuAnimation.presentationTransaction) {
                activeMenu = menu
            }
        }
    }

    private func dismissActiveMenu() {
        restoreFocusAfterMenuIfNeeded(preferImmediateResponder: true)
        withTransaction(HomeDetailMenuAnimation.dismissalTransaction) {
            activeMenu = nil
        }
    }

    private func makeRenderedChips(from snapshots: [TaskEditorChipSnapshot]) -> [TaskEditorRenderedChip] {
        snapshots.map { snapshot in
            TaskEditorRenderedChip(
                id: snapshot.id,
                title: snapshot.title,
                systemImage: snapshot.systemImage,
                menu: snapshot.menu,
                showsTrailingClear: snapshot.showsTrailingClear,
                transitionDirection: .up,
                semanticValue: snapshot.semanticValue
            )
        }
    }

}

private struct HomeDetailMenuPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}

private enum HomeDetailMenuAnimation {
    static let presentation = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let dismissal = Animation.spring(response: 0.4, dampingFraction: 0.94)

    static var presentationTransaction: Transaction {
        Transaction(animation: presentation)
    }

    static var dismissalTransaction: Transaction {
        Transaction(animation: dismissal)
    }
}

@MainActor
private final class DetailTextInputFocusCoordinator {
    weak var titleTextView: UITextView?
    weak var notesTextView: UITextView?
    private(set) var currentFocusedField: HomeItemDetailSheet.Field?
    private var pendingFocusField: HomeItemDetailSheet.Field?

    var isTransitioningFocus: Bool {
        pendingFocusField != nil
    }

    func register(_ textView: UITextView, for field: HomeItemDetailSheet.Field) {
        switch field {
        case .title:
            titleTextView = textView
        case .notes:
            notesTextView = textView
        }

        if pendingFocusField == field {
            DispatchQueue.main.async {
                self.requestFocus(for: field)
            }
        }
    }

    func resignCurrentResponder() {
        pendingFocusField = nil
        if titleTextView?.isFirstResponder == true {
            titleTextView?.resignFirstResponder()
        }
        if notesTextView?.isFirstResponder == true {
            notesTextView?.resignFirstResponder()
        }
    }

    func markDidBeginEditing(_ field: HomeItemDetailSheet.Field) {
        currentFocusedField = field
        pendingFocusField = nil
    }

    func markDidEndEditing(_ field: HomeItemDetailSheet.Field) {
        if currentFocusedField == field {
            currentFocusedField = nil
        }
    }

    func requestFocus(for field: HomeItemDetailSheet.Field) {
        pendingFocusField = field
        let target: UITextView?
        let other: UITextView?

        switch field {
        case .title:
            target = titleTextView
            other = notesTextView
        case .notes:
            target = notesTextView
            other = titleTextView
        }

        if other?.isFirstResponder == true {
            other?.resignFirstResponder()
        }
        guard let target, target.window != nil else { return }
        guard !target.isFirstResponder else {
            currentFocusedField = field
            pendingFocusField = nil
            return
        }
        target.becomeFirstResponder()
        currentFocusedField = field
        pendingFocusField = nil
    }
}

private struct DetailFocusableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focusedField: HomeItemDetailSheet.Field?
    let focusCoordinator: DetailTextInputFocusCoordinator
    let field: HomeItemDetailSheet.Field
    let placeholder: String
    let font: UIFont
    let textColor: UIColor
    let placeholderColor: UIColor
    let maximumNumberOfLines: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> DetailTextViewContainer {
        let container = DetailTextViewContainer()
        container.textView.delegate = context.coordinator
        focusCoordinator.register(container.textView, for: field)
        container.textView.backgroundColor = .clear
        container.textView.textContainerInset = .zero
        container.textView.textContainer.lineFragmentPadding = 0
        container.textView.isScrollEnabled = false
        container.textView.keyboardDismissMode = .interactive
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        container.textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.textView.setContentHuggingPriority(.required, for: .vertical)
        container.textView.setContentCompressionResistancePriority(.required, for: .vertical)
        container.onDidMoveToWindow = {
            context.coordinator.syncFirstResponder(in: container.textView)
        }

        update(container, coordinator: context.coordinator)
        return container
    }

    func updateUIView(_ uiView: DetailTextViewContainer, context: Context) {
        context.coordinator.parent = self
        focusCoordinator.register(uiView.textView, for: field)
        update(uiView, coordinator: context.coordinator)
        context.coordinator.syncFirstResponder(in: uiView.textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DetailTextViewContainer, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        guard targetWidth > 0 else {
            return uiView.intrinsicContentSize
        }
        return uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
    }

    private func update(_ container: DetailTextViewContainer, coordinator: Coordinator) {
        let textView = container.textView
        textView.font = font
        textView.textColor = textColor
        textView.textContainer.maximumNumberOfLines = maximumNumberOfLines
        textView.textContainer.lineBreakMode = .byTruncatingTail
        if textView.text != text {
            textView.text = text
        }
        container.placeholderLabel.text = placeholder
        container.placeholderLabel.font = font
        container.placeholderLabel.textColor = placeholderColor
        container.placeholderLabel.isHidden = !text.isEmpty
        container.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DetailFocusableTextView

        init(parent: DetailFocusableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let updated = textView.text ?? ""
            if parent.text != updated {
                parent.text = updated
            }
            if let container = textView.superview as? DetailTextViewContainer {
                container.placeholderLabel.isHidden = !updated.isEmpty
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focusCoordinator.markDidBeginEditing(parent.field)
            if parent.focusedField != parent.field {
                parent.focusedField = parent.field
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focusCoordinator.markDidEndEditing(parent.field)
            if parent.focusedField == parent.field && !parent.focusCoordinator.isTransitioningFocus {
                parent.focusedField = nil
            }
        }

        func syncFirstResponder(in textView: UITextView) {
            let shouldFocus = parent.focusedField == parent.field
            if shouldFocus {
                guard !textView.isFirstResponder else { return }
                guard textView.window != nil else { return }
                textView.becomeFirstResponder()
            } else if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }
}

private final class DetailTextViewContainer: UIView {
    let textView = UITextView()
    let placeholderLabel = UILabel()
    var onDidMoveToWindow: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(textView)
        addSubview(placeholderLabel)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.numberOfLines = 0
        placeholderLabel.backgroundColor = .clear

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onDidMoveToWindow?()
    }

    override var intrinsicContentSize: CGSize {
        let fallbackWidth = window?.windowScene?.screen.bounds.width ?? 320
        let fittingWidth = bounds.width > 0 ? bounds.width : fallbackWidth - 52
        let textHeight = textView.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(textHeight))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingWidth = size.width > 0 ? size.width : (bounds.width > 0 ? bounds.width : 320)
        let textHeight = textView.sizeThatFits(CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: fittingWidth, height: ceil(textHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

private enum HomeDetailMenu: String, Identifiable {
    case date
    case time
    case reminder
    case priority
    case repeatRule

    var id: String { rawValue }

    var detents: Set<PresentationDetent> {
        switch self {
        case .date:
            return [.custom(HomeDetailDateMenuDetent.self)]
        case .time:
            return [.fraction(0.5)]
        case .reminder, .priority, .repeatRule:
            return [.fraction(0.46)]
        }
    }
}

private struct HomeDetailDateMenuDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(
            HomeDetailDatePickerSheet.preferredHeight + 12,
            context.maxDetentValue * 0.72
        )
    }
}

private struct HomeDetailMenuSheet: View {
    let menu: TaskEditorMenu
    @Bindable var viewModel: HomeViewModel
    let onDismiss: () -> Void

    var body: some View {
        menuContent
            .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var menuContent: some View {
        switch menu {
        case .date:
            TaskEditorDatePickerSheet(
                selectedDate: detailDateBinding,
                selectionFeedback: HomeInteractionFeedback.selection,
                onDismiss: onDismiss
            )
        case .time:
            TaskEditorTimePickerSheet(
                selectedTime: detailTimeBinding,
                anchorDate: detailDateBinding.wrappedValue,
                quickPresetMinutes: viewModel.quickTimePresetMinutes,
                selectionFeedback: HomeInteractionFeedback.selection,
                primaryFeedback: HomeInteractionFeedback.selection,
                onDismiss: onDismiss
            )
        case .reminder:
            TaskEditorOptionList(
                options: reminderOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .priority:
            TaskEditorOptionList(
                options: priorityOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        case .repeatRule:
            TaskEditorOptionList(
                options: repeatOptions,
                selectionFeedback: HomeInteractionFeedback.selection
            )
        }
    }

    private var reminderOptions: [TaskEditorOptionRow] {
        [TaskEditorOptionRow(title: "不提醒", isSelected: viewModel.detailDraft?.remindAt == nil) {
            viewModel.setDraftReminderEnabled(false)
            onDismiss()
        }] + TaskEditorReminderPreset.allCases.map { preset in
            TaskEditorOptionRow(
                title: preset.title,
                isSelected: reminderTitle == preset.chipTitle
            ) {
                ensureDueDateExists()
                let dueAt = viewModel.detailDraft?.dueAt ?? .now
                viewModel.updateDraftReminder(dueAt.addingTimeInterval(-preset.secondsBeforeTarget))
                onDismiss()
            }
        }
    }

    private var priorityOptions: [TaskEditorOptionRow] {
        ItemPriority.allCases.map { priority in
            TaskEditorOptionRow(
                title: priority.title,
                isSelected: viewModel.detailDraft?.priority == priority
            ) {
                viewModel.updateDraftPriority(priority)
                onDismiss()
            }
        }
    }

    private var repeatOptions: [TaskEditorOptionRow] {
        let anchorDate = viewModel.detailDraft?.dueAt ?? defaultDetailDate
        let selectedTitle = repeatTitle
        return TaskEditorRepeatPreset.allCases.map { preset in
            let title = preset.title(anchorDate: anchorDate)
            return TaskEditorOptionRow(title: title, isSelected: selectedTitle == title) {
                ensureDueDateExists()
                viewModel.updateDraftRepeatRule(preset.makeRule(anchorDate: anchorDate))
                onDismiss()
            }
        }
    }

    private var reminderTitle: String {
        guard let remindAt = viewModel.detailDraft?.remindAt else { return "提醒" }
        guard let dueAt = viewModel.detailDraft?.dueAt else { return "提醒" }
        let delta = dueAt.timeIntervalSince(remindAt)
        return TaskEditorReminderPreset.preset(for: delta)?.chipTitle ?? "提醒"
    }

    private var repeatTitle: String {
        guard
            let rule = viewModel.detailDraft?.repeatRule,
            let dueAt = viewModel.detailDraft?.dueAt
        else {
            return "不重复"
        }
        return rule.title(anchorDate: dueAt, calendar: .current)
    }

    private var defaultDetailDate: Date {
        viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
    }

    private var detailDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.detailDraft?.dueAt ?? viewModel.selectedDate },
            set: { newValue in
                viewModel.updateDraftDueDate(newValue)
            }
        )
    }

    private var detailTimeBinding: Binding<Date?> {
        Binding(
            get: {
                guard viewModel.detailDraft?.hasExplicitTime == true else { return nil }
                return viewModel.detailDraft?.dueAt
            },
            set: { newValue in
                if let newValue {
                    viewModel.updateDraftDueTime(newValue)
                }
            }
        )
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }
}

private struct HomeDetailDatePickerSheet: View {
    static let gridRowHeight: CGFloat = 36
    static let gridRowSpacing: CGFloat = 10
    static let gridColumnSpacing: CGFloat = 0
    static let weekdayRowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 8
    static let topBottomPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 10
    static let headerToGridSpacing: CGFloat = 10
    static let calendarGridHeight: CGFloat =
        (gridRowHeight * 6)
        + (gridRowSpacing * 5)
    static let preferredHeight: CGFloat =
        (topBottomPadding * 2)
        + headerHeight
        + headerToGridSpacing
        + weekdayRowHeight
        + contentSpacing
        + calendarGridHeight

    @Bindable var viewModel: HomeViewModel
    let onDismiss: () -> Void
    @State private var displayedMonth: Date
    @State private var transitionDirection: HomeDetailMonthTransitionDirection = .forward

    init(viewModel: HomeViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss

        let calendar = Calendar.current
        let initialDate = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        _displayedMonth = State(
            initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let headerInset = headerHorizontalInset(for: proxy.size.width)

            VStack(alignment: .leading, spacing: Self.headerToGridSpacing) {
                HStack(spacing: 10) {
                    Text(monthTitle)
                        .font(AppTheme.typography.sized(21, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        calendarButton(systemName: "chevron.left") {
                            shiftMonth(by: -1)
                        }

                        Button("Today") {
                            HomeInteractionFeedback.selection()
                            selectDate(Date())
                        }
                        .buttonStyle(.plain)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(minWidth: 84, minHeight: 40)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )

                        calendarButton(systemName: "chevron.right") {
                            shiftMonth(by: 1)
                        }
                    }
                }
                .frame(height: Self.headerHeight)
                .padding(.horizontal, headerInset)

                VStack(spacing: Self.contentSpacing) {
                    LazyVGrid(
                        columns: calendarColumns,
                        spacing: Self.gridColumnSpacing
                    ) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(AppTheme.typography.sized(14, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.weekdayRowHeight)
                        }
                    }

                    LazyVGrid(
                        columns: calendarColumns,
                        spacing: Self.gridRowSpacing
                    ) {
                        ForEach(monthCells) { cell in
                            Button {
                                HomeInteractionFeedback.selection()
                                selectDate(cell.date)
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(
                                            isToday(cell.date) && !isSelected(cell.date)
                                            ? AppTheme.colors.coral
                                            : .clear,
                                            lineWidth: 1.6
                                        )
                                        .background(
                                            Circle()
                                                .fill(isSelected(cell.date) ? AppTheme.colors.coral : .clear)
                                        )

                                    Text("\(Calendar.current.component(.day, from: cell.date))")
                                        .font(AppTheme.typography.sized(18, weight: .semibold))
                                        .foregroundStyle(dayTextColor(for: cell))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.gridRowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(height: Self.calendarGridHeight, alignment: .top)
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .id(monthIdentity)
        .transition(monthTransition)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: displayedMonth)
        .padding(.vertical, Self.topBottomPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gridColumnSpacing), count: 7)
    }

    private func headerHorizontalInset(for availableWidth: CGFloat) -> CGFloat {
        let gridWidth = max(availableWidth - (Self.horizontalPadding * 2), 0)
        let columnWidth = max((gridWidth - (Self.gridColumnSpacing * 6)) / 7, 0)
        let firstColumnCenterX = Self.horizontalPadding + (columnWidth / 2)
        let visualDayHalfWidth = min(widestDayLabelWidth, columnWidth) / 2
        return max(firstColumnCenterX - visualDayHalfWidth, Self.horizontalPadding)
    }

    private var selectedDate: Date {
        viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var monthIdentity: String {
        let components = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private var monthTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: transitionDirection.insertionEdge).combined(with: .opacity),
            removal: .move(edge: transitionDirection.removalEdge).combined(with: .opacity)
        )
    }

    private var widestDayLabelWidth: CGFloat {
        #if canImport(UIKit)
        let font = AppTheme.typography.sizedUIFont(18, weight: .semibold)
        return (1...31)
            .map { "\($0)" }
            .map { NSString(string: $0).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        #else
        return 0
        #endif
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthCells: [HomeDetailCalendarDayCell] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var cells: [HomeDetailCalendarDayCell] = []
        var current = firstWeek.start
        while current < lastWeek.end {
            cells.append(
                HomeDetailCalendarDayCell(
                    date: current,
                    isInDisplayedMonth: calendar.isDate(current, equalTo: displayedMonth, toGranularity: .month)
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }
        return cells
    }

    private func calendarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(AppTheme.typography.sized(15, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        transitionDirection = amount >= 0 ? .forward : .backward
        HomeInteractionFeedback.selection()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            displayedMonth = next
        }
    }

    private func selectDate(_ date: Date) {
        viewModel.updateDraftDueDate(Calendar.current.startOfDay(for: date))
        onDismiss()
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayTextColor(for cell: HomeDetailCalendarDayCell) -> Color {
        if isSelected(cell.date) {
            return .white
        }
        if isToday(cell.date) {
            return AppTheme.colors.coral
        }
        return cell.isInDisplayedMonth ? AppTheme.colors.title : AppTheme.colors.textTertiary.opacity(0.52)
    }
}

private struct HomeDetailTimePickerSheet: View {
    @Bindable var viewModel: HomeViewModel
    let quickPresetMinutes: [Int]
    let onDismiss: () -> Void
    @State private var selectedTime: Date

    init(
        viewModel: HomeViewModel,
        quickPresetMinutes: [Int],
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.quickPresetMinutes = NotificationSettings.normalizedQuickTimePresetMinutes(quickPresetMinutes)
        self.onDismiss = onDismiss

        let detailDate = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        let baseTime = viewModel.detailDraft?.dueAt
            ?? Self.roundedTimeSeed(for: detailDate)
            ?? detailDate
        _selectedTime = State(initialValue: baseTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(quickPresetMinutes, id: \.self) { minutes in
                    Button {
                        HomeInteractionFeedback.selection()
                        applyQuickPreset(minutes)
                    } label: {
                        Text(relativePresetTitle(minutes))
                            .font(AppTheme.typography.sized(15, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(HomeDetailMenuOptionButtonStyle())
                    .modifier(HomeDetailMenuOptionGlassModifier())
                }
            }
            .padding(.top, HomeDetailTimePickerMetrics.verticalInset)
            .padding(.horizontal, HomeDetailMenuOptionMetrics.outerInset)
            .padding(.bottom, HomeDetailTimePickerMetrics.contentSpacing)

            TaskEditorSingleColumnTimeWheel(
                selection: $selectedTime,
                minuteInterval: 5
            )
            .frame(maxWidth: .infinity)
            .frame(height: HomeDetailTimePickerMetrics.pickerHeight)
            .clipped()
            .padding(.bottom, HomeDetailTimePickerMetrics.contentSpacing)

            HStack {
                Button {
                    HomeInteractionFeedback.selection()
                    saveSelection()
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        Text("添加")
                            .font(AppTheme.typography.sized(17, weight: .semibold))
                            .foregroundStyle(AppTheme.colors.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: HomeDetailMenuOptionMetrics.height)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                            style: .continuous
                        )
                    )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(HomeDetailMenuOptionButtonStyle())
                .modifier(HomeDetailMenuOptionGlassModifier())
            }
            .padding(.horizontal, HomeDetailMenuOptionMetrics.outerInset)
            .padding(.bottom, HomeDetailTimePickerMetrics.verticalInset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private static func roundedTimeSeed(for date: Date) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let roundedMinute = Int((Double(minute) / 5).rounded()) * 5
        let minuteOverflow = roundedMinute / 60
        let normalizedMinute = roundedMinute % 60
        let normalizedHour = (hour + minuteOverflow) % 24

        return calendar.date(
            bySettingHour: normalizedHour,
            minute: normalizedMinute,
            second: 0,
            of: date
        )
    }

    private static func offsetTimeSeed(minutesFromNow: Int, for date: Date) -> Date {
        let calendar = Calendar.current
        let future = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        let components = calendar.dateComponents([.hour, .minute], from: future)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    private func applyQuickPreset(_ minutes: Int) {
        let date = viewModel.detailDraft?.dueAt ?? viewModel.selectedDate
        let presetTime = Self.offsetTimeSeed(minutesFromNow: minutes, for: date)
        selectedTime = presetTime
        saveSelection(presetTime)
    }

    private func relativePresetTitle(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)小时后"
        }
        return "\(minutes)分钟后"
    }

    private func saveSelection(_ value: Date? = nil) {
        ensureDueDateExists()
        viewModel.updateDraftDueTime(value ?? selectedTime)
        onDismiss()
    }

    private func ensureDueDateExists() {
        guard viewModel.detailDraft?.dueAt == nil else { return }
        viewModel.setDraftDueDateEnabled(true)
    }
}

private struct HomeDetailMinuteIntervalWheelPicker: UIViewRepresentable {
    @Binding var selection: Date
    let minuteInterval: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.locale = Locale(identifier: "zh_CN")
        picker.minuteInterval = minuteInterval
        picker.setDate(Self.rounded(selection, minuteInterval: minuteInterval), animated: false)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.didChange(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        let roundedSelection = Self.rounded(selection, minuteInterval: minuteInterval)

        if abs(selection.timeIntervalSince(roundedSelection)) > 0.5 {
            DispatchQueue.main.async {
                selection = roundedSelection
            }
        }

        if abs(uiView.date.timeIntervalSince(roundedSelection)) > 0.5 {
            uiView.setDate(roundedSelection, animated: context.coordinator.hasAppeared)
        }

        context.coordinator.hasAppeared = true
    }

    private static func rounded(_ date: Date, minuteInterval: Int) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let roundedMinute = Int((Double(minute) / Double(minuteInterval)).rounded()) * minuteInterval

        let hourBaseDate = calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date

        return calendar.date(byAdding: .minute, value: roundedMinute, to: hourBaseDate) ?? hourBaseDate
    }

    final class Coordinator: NSObject {
        var parent: HomeDetailMinuteIntervalWheelPicker
        var hasAppeared = false

        init(_ parent: HomeDetailMinuteIntervalWheelPicker) {
            self.parent = parent
        }

        @objc func didChange(_ sender: UIDatePicker) {
            parent.selection = HomeDetailMinuteIntervalWheelPicker.rounded(
                sender.date,
                minuteInterval: parent.minuteInterval
            )
        }
    }
}

private struct HomeDetailOptionRow: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

private struct HomeDetailCalendarDayCell: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

private enum HomeDetailMonthTransitionDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        switch self {
        case .forward:
            return .trailing
        case .backward:
            return .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward:
            return .leading
        case .backward:
            return .trailing
        }
    }
}

private enum HomeDetailReminderPreset: CaseIterable, Identifiable {
    case atTime
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay

    var id: String { title }

    var secondsBeforeTarget: TimeInterval {
        switch self {
        case .atTime:
            return 0
        case .fiveMinutes:
            return 300
        case .fifteenMinutes:
            return 900
        case .thirtyMinutes:
            return 1_800
        case .oneHour:
            return 3_600
        case .oneDay:
            return 86_400
        }
    }

    var title: String {
        switch self {
        case .atTime:
            return "准时提醒"
        case .fiveMinutes:
            return "提前 5 分钟"
        case .fifteenMinutes:
            return "提前 15 分钟"
        case .thirtyMinutes:
            return "提前 30 分钟"
        case .oneHour:
            return "提前 1 小时"
        case .oneDay:
            return "提前 1 天"
        }
    }

    var chipTitle: String {
        switch self {
        case .atTime:
            return "准时"
        case .fiveMinutes:
            return "5 分钟"
        case .fifteenMinutes:
            return "15 分钟"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .oneDay:
            return "1 天"
        }
    }

    static func preset(for secondsBeforeTarget: TimeInterval) -> HomeDetailReminderPreset? {
        allCases.first { $0.secondsBeforeTarget == secondsBeforeTarget }
    }
}

private enum HomeDetailRepeatPreset: CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case weekdays
    case biweekly
    case quarterly
    case halfYear

    var id: String { String(describing: self) }

    func title(anchorDate: Date) -> String {
        makeRule(anchorDate: anchorDate).title(anchorDate: anchorDate)
    }

    func makeRule(anchorDate: Date) -> ItemRepeatRule {
        let calendar = Calendar.current
        switch self {
        case .daily:
            return ItemRepeatRule(frequency: .daily)
        case .weekly:
            return ItemRepeatRule(
                frequency: .weekly,
                weekday: calendar.component(.weekday, from: anchorDate)
            )
        case .monthly:
            return ItemRepeatRule(
                frequency: .monthly,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        case .weekdays:
            return ItemRepeatRule(
                frequency: .weekly,
                weekdays: [2, 3, 4, 5, 6]
            )
        case .biweekly:
            return ItemRepeatRule(
                frequency: .weekly,
                interval: 2,
                weekday: calendar.component(.weekday, from: anchorDate)
            )
        case .quarterly:
            return ItemRepeatRule(
                frequency: .monthly,
                interval: 3,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        case .halfYear:
            return ItemRepeatRule(
                frequency: .monthly,
                interval: 6,
                dayOfMonth: calendar.component(.day, from: anchorDate)
            )
        }
    }
}

private struct HomeDetailMenuOptionGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: HomeDetailMenuOptionMetrics.cornerRadius,
                        style: .continuous
                    )
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                }
        }
    }
}

private struct HomeDetailMenuOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private enum HomeDetailMenuOptionMetrics {
    static let outerInset: CGFloat = 18
    static let height: CGFloat = 66
    static let cornerRadius: CGFloat = 26
}

private enum HomeDetailTimePickerMetrics {
    static let verticalInset: CGFloat = 18
    static let contentSpacing: CGFloat = 12
    static let pickerHeight: CGFloat = 170
}
