import SwiftUI

struct HomeItemEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: FocusField?

    let item: Item
    @Binding var draft: HomeEditorDraft
    let ownershipTokens: [HomeAvatarToken]
    let isStageVisible: Bool
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var activePanel: EditorPanel?
    @State private var focusTask: Task<Void, Never>?
    @State private var contentRevealed = false

    private enum FocusField {
        case title
        case notes
    }

    private enum EditorPanel: String, Identifiable {
        case dueAt
        case executionRole
        case location
        case priority

        var id: String { rawValue }
    }

    var body: some View {
        let palette = palette

        VStack(alignment: .leading, spacing: 18) {
            liftedCard(palette: palette)
                .frame(maxHeight: .infinity, alignment: .top)

            lowerSection(palette: palette)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(palette.containerTint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .strokeBorder(palette.chromeBorder, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 22, y: 10)
        .overlay(alignment: .bottom) {
            if let activePanel {
                panelOverlay(for: activePanel, palette: palette)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 74)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: activePanel)
        .onAppear {
            focusTask?.cancel()
            focusedField = nil
            contentRevealed = isStageVisible
            focusTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                focusedField = .title
            }
        }
        .onChange(of: isStageVisible) { _, isVisible in
            guard isVisible else {
                withAnimation(.easeOut(duration: 0.12)) {
                    contentRevealed = false
                }
                return
            }

            withAnimation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.08)) {
                contentRevealed = true
            }
        }
        .onDisappear {
            focusTask?.cancel()
            focusTask = nil
            focusedField = nil
            contentRevealed = false
        }
    }

    private func liftedCard(palette: EditorPalette) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text(draft.dueAt, format: .dateTime.hour().minute())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.timeText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.timePillFill, in: Capsule())

                Spacer(minLength: 0)

                Button {
                    draft.isPinned.toggle()
                } label: {
                    Image(systemName: draft.isPinned ? "pin.fill" : "pin")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.accessoryText)
                        .frame(width: 32, height: 32)
                        .background(palette.accessoryFill, in: Circle())
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(palette.accessoryText)
                        .frame(width: 32, height: 32)
                        .background(palette.accessoryFill, in: Circle())
                }
                .buttonStyle(.plain)
            }

            TextField("事项标题", text: $draft.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(-0.45)
                .lineSpacing(1)
                .foregroundStyle(palette.primaryText)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)

            TextField("补充说明", text: $draft.notes, axis: .vertical)
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .tracking(-0.2)
                .lineSpacing(3)
                .foregroundStyle(palette.secondaryText)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .focused($focusedField, equals: .notes)

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)

                HStack(spacing: -8) {
                    ForEach(ownershipTokensForDraft) { token in
                        Text(token.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.avatarText)
                            .frame(width: 36, height: 36)
                            .background(palette.avatarFill, in: Circle())
                            .overlay(Circle().stroke(palette.avatarStroke, lineWidth: 1))
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 1)
        )
    }

    private func lowerSection(palette: EditorPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                inlineAttributeButton(
                    systemImage: "clock",
                    title: dueInlineSummary,
                    panel: .dueAt,
                    palette: palette
                )

                inlineAttributeButton(
                    systemImage: "bell",
                    title: reminderInlineSummary,
                    panel: .dueAt,
                    palette: palette
                )

                inlineAttributeButton(
                    systemImage: "hourglass",
                    title: countdownInlineSummary,
                    panel: .dueAt,
                    palette: palette
                )

                Spacer(minLength: 0)
            }
            .cascadeRow(index: 0, revealed: contentRevealed)

            HStack(spacing: 18) {
                inlineAttributeButton(
                    systemImage: "mappin.and.ellipse",
                    title: locationInlineSummary,
                    panel: .location,
                    palette: palette
                )

                Spacer(minLength: 0)
            }
            .cascadeRow(index: 1, revealed: contentRevealed)

            HStack(spacing: 18) {
                inlineAttributeButton(
                    systemImage: "flag",
                    title: draft.priority.title,
                    panel: .priority,
                    palette: palette
                )

                inlineAttributeButton(
                    systemImage: "person.2",
                    title: executionRoleSummary,
                    panel: .executionRole,
                    palette: palette
                )

                Spacer(minLength: 0)
            }
            .cascadeRow(index: 2, revealed: contentRevealed)

            actionBar(palette: palette)
                .padding(.top, 6)
                .cascadeRow(index: 3, revealed: contentRevealed)
        }
        .padding(.horizontal, 22)
    }

    private func inlineAttributeButton(
        systemImage: String,
        title: String,
        panel: EditorPanel,
        palette: EditorPalette
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                activePanel = activePanel == panel ? nil : panel
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(activePanel == panel ? palette.attributeActiveText : palette.attributeIcon)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(activePanel == panel ? palette.attributeActiveText : palette.attributeValue)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionBar(palette: EditorPalette) -> some View {
        HStack(spacing: 12) {
            Button("关闭") {
                activePanel = nil
                onClose()
            }
            .font(.headline.weight(.medium))
            .foregroundStyle(palette.dismissText)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(palette.chromeBorder, lineWidth: 1)
            )

            Spacer(minLength: 0)

            Button("保存", action: onSave)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.saveText)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(palette.saveFill, in: Capsule())
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func panelOverlay(for panel: EditorPanel, palette: EditorPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch panel {
            case .dueAt:
                Text("时间")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                DatePicker("", selection: $draft.dueAt)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(palette.highlight)

                Toggle("提醒", isOn: reminderEnabledBinding)
                    .tint(palette.highlight)

                if draft.remindAt != nil {
                    Picker("提前提醒", selection: reminderLeadMinutesBinding) {
                        Text("5m").tag(5)
                        Text("15m").tag(15)
                        Text("30m").tag(30)
                    }
                    .pickerStyle(.segmented)
                }

            case .executionRole:
                Text("执行人")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                Picker("执行人", selection: $draft.executionRole) {
                    Text("我").tag(ItemExecutionRole.initiator)
                    Text("TA").tag(ItemExecutionRole.recipient)
                    Text("一起").tag(ItemExecutionRole.both)
                }
                .pickerStyle(.segmented)

            case .location:
                Text("地点")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                TextField("搜索地点或填写地点摘要", text: $draft.locationText)
                    .font(.body.weight(.medium))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(palette.panelInputFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            case .priority:
                Text("优先级")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)

                Picker("优先级", selection: $draft.priority) {
                    ForEach(ItemPriority.allCases, id: \.self) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(palette.chromeBorder, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 18, y: 8)
    }

    private var dateSummary: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(draft.dueAt) {
            return draft.dueAt.formatted(.dateTime.hour().minute())
        }

        return draft.dueAt.formatted(.dateTime.month().day().hour().minute())
    }

    private var compactDateSummary: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(draft.dueAt) {
            return draft.dueAt.formatted(.dateTime.hour().minute())
        }

        return draft.dueAt.formatted(.dateTime.month().day())
    }

    private var dueInlineSummary: String {
        let calendar = Calendar.current
        let time = draft.dueAt.formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )

        if calendar.isDateInToday(draft.dueAt) {
            return "今天,\(time)"
        }

        if calendar.isDateInTomorrow(draft.dueAt) {
            return "明天,\(time)"
        }

        let month = calendar.component(.month, from: draft.dueAt)
        let day = calendar.component(.day, from: draft.dueAt)
        return "\(month)月\(day)日,\(time)"
    }

    private var executionRoleSummary: String {
        switch draft.executionRole {
        case .initiator:
            "我负责"
        case .recipient:
            "TA负责"
        case .both:
            "一起完成"
        }
    }

    private var executionRoleShortSummary: String {
        switch draft.executionRole {
        case .initiator:
            "我"
        case .recipient:
            "TA"
        case .both:
            "一起"
        }
    }

    private var locationSummary: String {
        let trimmed = draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "添加" }
        return trimmed
    }

    private var compactLocationSummary: String {
        let trimmed = draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "添加" }
        if trimmed.count <= 4 { return trimmed }
        return String(trimmed.prefix(4))
    }

    private var locationInlineSummary: String {
        let trimmed = draft.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "添加地点" : trimmed
    }

    private var reminderInlineSummary: String {
        guard let remindAt = draft.remindAt else { return "不提醒" }
        let minutes = max(1, Int(draft.dueAt.timeIntervalSince(remindAt) / 60))
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = max(1, minutes / 60)
        return "\(hours)h"
    }

    private var countdownInlineSummary: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: draft.dueAt, relativeTo: Date())
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.remindAt != nil },
            set: { isEnabled in
                draft.remindAt = isEnabled ? draft.dueAt.addingTimeInterval(-300) : nil
            }
        )
    }

    private var reminderLeadMinutesBinding: Binding<Int> {
        Binding(
            get: {
                guard let remindAt = draft.remindAt else { return 5 }
                return max(5, Int(draft.dueAt.timeIntervalSince(remindAt) / 60))
            },
            set: { minutes in
                draft.remindAt = draft.dueAt.addingTimeInterval(TimeInterval(-minutes * 60))
            }
        )
    }

    private var ownershipTokensForDraft: [HomeAvatarToken] {
        let meToken = ownershipTokens.first(where: { $0.title == "我" })
        let partnerToken = ownershipTokens.first(where: { $0.title == "TA" })

        switch draft.executionRole {
        case .initiator:
            return Array([meToken].compactMap { $0 }.prefix(1))
        case .recipient:
            return Array([partnerToken].compactMap { $0 }.prefix(1))
        case .both:
            return [meToken, partnerToken].compactMap { $0 }
        }
    }

    private var palette: EditorPalette {
        let isAccent = draft.isPinned || draft.priority != .normal

        return switch (isAccent, colorScheme) {
        case (true, .dark):
            EditorPalette(
                containerTint: .clear,
                cardBackground: Color(red: 0.067, green: 0.067, blue: 0.075),
                cardBorder: Color(red: 0.165, green: 0.165, blue: 0.192),
                chromeBorder: Color.white.opacity(0.08),
                primaryText: Color(red: 0.957, green: 0.686, blue: 0.753),
                secondaryText: Color(red: 0.820, green: 0.604, blue: 0.667),
                timeText: Color(red: 0.925, green: 0.631, blue: 0.702),
                timePillFill: Color(red: 0.110, green: 0.110, blue: 0.133),
                accessoryText: Color(red: 0.957, green: 0.686, blue: 0.753),
                accessoryFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarText: Color(red: 0.949, green: 0.694, blue: 0.757),
                avatarStroke: Color(red: 0.953, green: 0.604, blue: 0.690).opacity(0.24),
                attributeFill: Color.white.opacity(0.07),
                attributeActiveFill: Color(red: 0.953, green: 0.604, blue: 0.690).opacity(0.18),
                attributeBorder: Color.white.opacity(0.05),
                attributeActiveBorder: Color(red: 0.953, green: 0.604, blue: 0.690).opacity(0.24),
                attributeLabel: Color(red: 0.847, green: 0.640, blue: 0.708),
                attributeValue: Color(red: 0.994, green: 0.942, blue: 0.969),
                attributeIcon: Color(red: 0.847, green: 0.640, blue: 0.708),
                attributeActiveText: Color(red: 0.976, green: 0.844, blue: 0.894),
                panelInputFill: Color.white.opacity(0.06),
                dismissFill: .clear,
                dismissText: Color(red: 0.949, green: 0.933, blue: 0.914),
                saveFill: Color(red: 0.776, green: 0.282, blue: 0.463),
                saveText: Color.white,
                highlight: Color(red: 0.957, green: 0.686, blue: 0.753)
            )
        case (true, _):
            EditorPalette(
                containerTint: .clear,
                cardBackground: Color(red: 0.918, green: 0.498, blue: 0.600),
                cardBorder: Color.white.opacity(0.14),
                chromeBorder: Color.black.opacity(0.04),
                primaryText: Color(red: 0.189, green: 0.115, blue: 0.159),
                secondaryText: Color(red: 0.333, green: 0.210, blue: 0.263),
                timeText: Color(red: 0.996, green: 0.972, blue: 0.984),
                timePillFill: Color.white.opacity(0.14),
                accessoryText: Color(red: 0.996, green: 0.972, blue: 0.984),
                accessoryFill: Color.white.opacity(0.14),
                avatarFill: Color(red: 1.0, green: 0.969, blue: 0.980),
                avatarText: Color(red: 0.788, green: 0.353, blue: 0.490),
                avatarStroke: Color.white.opacity(0.4),
                attributeFill: Color(red: 0.974, green: 0.905, blue: 0.934),
                attributeActiveFill: Color(red: 0.967, green: 0.860, blue: 0.906),
                attributeBorder: Color(red: 0.706, green: 0.336, blue: 0.472).opacity(0.10),
                attributeActiveBorder: Color(red: 0.706, green: 0.336, blue: 0.472).opacity(0.18),
                attributeLabel: Color(red: 0.706, green: 0.336, blue: 0.472).opacity(0.82),
                attributeValue: Color(red: 0.200, green: 0.118, blue: 0.165),
                attributeIcon: Color(red: 0.706, green: 0.336, blue: 0.472).opacity(0.82),
                attributeActiveText: Color(red: 0.576, green: 0.214, blue: 0.376),
                panelInputFill: Color.white.opacity(0.16),
                dismissFill: .clear,
                dismissText: Color(red: 0.189, green: 0.115, blue: 0.159),
                saveFill: Color(red: 0.776, green: 0.282, blue: 0.463),
                saveText: Color.white,
                highlight: Color.white
            )
        case (false, .dark):
            EditorPalette(
                containerTint: .clear,
                cardBackground: Color(red: 0.067, green: 0.067, blue: 0.075),
                cardBorder: Color(red: 0.165, green: 0.165, blue: 0.192),
                chromeBorder: Color.white.opacity(0.08),
                primaryText: Color(red: 0.949, green: 0.933, blue: 0.914),
                secondaryText: Color(red: 0.745, green: 0.714, blue: 0.690),
                timeText: Color(red: 0.831, green: 0.804, blue: 0.776),
                timePillFill: Color.white.opacity(0.04),
                accessoryText: Color(red: 0.831, green: 0.804, blue: 0.776),
                accessoryFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarText: Color(red: 0.949, green: 0.933, blue: 0.914),
                avatarStroke: Color(red: 0.184, green: 0.184, blue: 0.216),
                attributeFill: Color.white.opacity(0.06),
                attributeActiveFill: Color.white.opacity(0.10),
                attributeBorder: Color.white.opacity(0.05),
                attributeActiveBorder: Color.white.opacity(0.10),
                attributeLabel: Color(red: 0.788, green: 0.760, blue: 0.733),
                attributeValue: Color(red: 0.968, green: 0.952, blue: 0.932),
                attributeIcon: Color(red: 0.788, green: 0.760, blue: 0.733),
                attributeActiveText: Color.white,
                panelInputFill: Color.white.opacity(0.06),
                dismissFill: .clear,
                dismissText: Color(red: 0.949, green: 0.933, blue: 0.914),
                saveFill: Color(red: 0.776, green: 0.282, blue: 0.463),
                saveText: Color.white,
                highlight: Color(red: 0.949, green: 0.933, blue: 0.914)
            )
        default:
            EditorPalette(
                containerTint: .clear,
                cardBackground: Color.white,
                cardBorder: Color.black.opacity(0.06),
                chromeBorder: Color.black.opacity(0.04),
                primaryText: Color(red: 0.090, green: 0.090, blue: 0.102),
                secondaryText: Color(red: 0.463, green: 0.463, blue: 0.502),
                timeText: Color(red: 0.420, green: 0.420, blue: 0.447),
                timePillFill: Color(red: 0.955, green: 0.955, blue: 0.965),
                accessoryText: Color(red: 0.420, green: 0.420, blue: 0.447),
                accessoryFill: Color(red: 0.955, green: 0.955, blue: 0.965),
                avatarFill: Color(red: 0.078, green: 0.078, blue: 0.086),
                avatarText: .white,
                avatarStroke: Color.black.opacity(0.08),
                attributeFill: Color(red: 0.948, green: 0.949, blue: 0.957),
                attributeActiveFill: Color(red: 0.936, green: 0.938, blue: 0.950),
                attributeBorder: Color.black.opacity(0.04),
                attributeActiveBorder: Color.black.opacity(0.07),
                attributeLabel: Color(red: 0.505, green: 0.505, blue: 0.548),
                attributeValue: Color(red: 0.090, green: 0.090, blue: 0.102),
                attributeIcon: Color(red: 0.505, green: 0.505, blue: 0.548),
                attributeActiveText: Color(red: 0.090, green: 0.090, blue: 0.102),
                panelInputFill: Color(red: 0.965, green: 0.965, blue: 0.972),
                dismissFill: .clear,
                dismissText: Color(red: 0.090, green: 0.090, blue: 0.102),
                saveFill: Color(red: 0.776, green: 0.282, blue: 0.463),
                saveText: Color.white,
                highlight: Color(red: 0.918, green: 0.498, blue: 0.600)
            )
        }
    }
}

private struct EditorPalette {
    let containerTint: Color
    let cardBackground: Color
    let cardBorder: Color
    let chromeBorder: Color
    let primaryText: Color
    let secondaryText: Color
    let timeText: Color
    let timePillFill: Color
    let accessoryText: Color
    let accessoryFill: Color
    let avatarFill: Color
    let avatarText: Color
    let avatarStroke: Color
    let attributeFill: Color
    let attributeActiveFill: Color
    let attributeBorder: Color
    let attributeActiveBorder: Color
    let attributeLabel: Color
    let attributeValue: Color
    let attributeIcon: Color
    let attributeActiveText: Color
    let panelInputFill: Color
    let dismissFill: Color
    let dismissText: Color
    let saveFill: Color
    let saveText: Color
    let highlight: Color
}

private struct CascadeRow: ViewModifier {
    let index: Int
    let revealed: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : CGFloat(10 + (index * 6)))
            .animation(
                .spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.08)
                    .delay(Double(index) * 0.04),
                value: revealed
            )
    }
}

private extension View {
    func cascadeRow(index: Int, revealed: Bool) -> some View {
        modifier(CascadeRow(index: index, revealed: revealed))
    }
}
