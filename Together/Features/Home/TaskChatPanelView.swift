import SwiftUI

struct TaskChatPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: TaskChatViewModel
    let currentUserID: UUID?
    let partnerAvatar: HomeAvatar?
    let currentUserAvatar: HomeAvatar?
    let onDismiss: () -> Void

    private let bottomAnchorID = "task-chat-bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: AppTheme.radius.xxl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.xxl, style: .continuous)
                .stroke(AppTheme.colors.pillOutline, lineWidth: 1)
        }
        .shadow(color: AppTheme.colors.shadow.opacity(0.16), radius: 28, y: 16)
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                Text(viewModel.task.title)
                    .font(AppTheme.typography.sized(19, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(viewModel.canSend ? "任务聊天" : "任务已完成，留言已关闭")
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(AppTheme.typography.sized(14, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(AppTheme.colors.surfaceElevated.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭任务聊天")
        }
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.top, AppTheme.spacing.md)
        .padding(.bottom, AppTheme.spacing.sm)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppTheme.spacing.sm) {
                    ForEach(viewModel.entries) { entry in
                        row(for: entry)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: viewModel.entries.count) {
                await Task.yield()
                if reduceMotion {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                } else {
                    withAnimation(AppTheme.motion.micro) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: TaskChatTimelineEntry) -> some View {
        switch entry {
        case .system(_, let text, _):
            systemRow(text)
        case .nudge(let message):
            nudgeRow(message)
        case .comment(let message):
            commentRow(message)
        }
    }

    private func systemRow(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.typography.sized(12, weight: .semibold))
            .foregroundStyle(AppTheme.colors.body.opacity(0.58))
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated.opacity(0.74))
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(text)
    }

    private func nudgeRow(_ message: TaskMessage) -> some View {
        let isMe = message.senderID == currentUserID
        let text = isMe ? "你提醒了对方" : "\(partnerAvatar?.displayName ?? "对方")提醒了你"

        return HStack(spacing: AppTheme.spacing.xs) {
            Image(systemName: "bell.badge.fill")
                .font(AppTheme.typography.sized(11, weight: .semibold))
            Text(text)
                .font(AppTheme.typography.sized(12, weight: .semibold))
        }
        .foregroundStyle(AppTheme.colors.coral.opacity(0.76))
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.colors.coral.opacity(0.10))
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(text)
    }

    private func commentRow(_ message: TaskMessage) -> some View {
        let isMe = message.senderID == currentUserID

        return HStack(alignment: .bottom, spacing: AppTheme.spacing.sm) {
            if isMe {
                Spacer(minLength: 44)
            } else {
                avatar(for: message.senderID)
            }

            Text(message.content ?? "")
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.sm)
                .background(
                    bubbleFill(isMe: isMe),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .frame(maxWidth: 280, alignment: isMe ? .trailing : .leading)
                .layoutPriority(1)

            if isMe {
                avatar(for: message.senderID)
            } else {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }

    private func bubbleFill(isMe: Bool) -> Color {
        if isMe {
            return AppTheme.colors.coral.opacity(0.14)
        }
        return AppTheme.colors.sky.opacity(0.14)
    }

    @ViewBuilder
    private func avatar(for userID: UUID) -> some View {
        let avatar = userID == currentUserID ? currentUserAvatar : partnerAvatar
        if let avatar {
            UserAvatarView(
                avatarAsset: avatar.avatarAsset,
                displayName: avatar.displayName,
                size: 32,
                fillColor: AppTheme.colors.surfaceElevated,
                symbolColor: AppTheme.colors.textTertiary,
                symbolFont: AppTheme.typography.sized(13, weight: .semibold),
                overrideImage: avatar.overrideImage
            )
        } else {
            Circle()
                .fill(AppTheme.colors.surfaceElevated)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.textTertiary)
                }
        }
    }

    private var composer: some View {
        VStack(spacing: AppTheme.spacing.xs) {
            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(AppTheme.typography.sized(12, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: AppTheme.spacing.sm) {
                TextField(
                    viewModel.canSend ? "写一句回复..." : "任务已完成，不能继续留言",
                    text: $viewModel.draftText,
                    axis: .vertical
                )
                .font(AppTheme.typography.sized(15, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.colors.surface.opacity(0.82))
                )
                .disabled(viewModel.canSend == false || viewModel.isSending)

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(sendButtonColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isSendDisabled)
                .accessibilityLabel("发送留言")
            }
        }
        .padding(AppTheme.spacing.md)
        .background(.bar)
    }

    private var isSendDisabled: Bool {
        viewModel.canSend == false
            || viewModel.isSending
            || viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonColor: Color {
        isSendDisabled ? AppTheme.colors.textTertiary.opacity(0.56) : AppTheme.colors.coral
    }
}
