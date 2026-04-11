import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 双人模式下的 Profile 编辑界面
/// 显示双方头像（自己可编辑，对方只读），可修改昵称和共享空间名称
struct EditPairProfileView: View {
    @Bindable var viewModel: EditProfileViewModel
    let partnerAvatar: ProfileCardAvatar
    let partnerName: String
    let spaceName: String
    let onSpaceNameChanged: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showsDiscardAlert = false
    @State private var editableSpaceName: String = ""
    @State private var cameraCaptureToken = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xl) {
                avatarPairSection
                nameSection
                spaceNameSection
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("编辑双人资料")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("返回") {
                    HomeInteractionFeedback.selection()
                    handleDismissTapped()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    HomeInteractionFeedback.selection()
                    Task { @MainActor in
                        // 保存空间名称
                        let trimmedSpaceName = editableSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedSpaceName != spaceName {
                            onSpaceNameChanged(trimmedSpaceName)
                        }
                        // 保存个人资料
                        let didSave = await viewModel.save()
                        if didSave {
                            HomeInteractionFeedback.completion()
                            dismiss()
                        }
                    }
                }
                .disabled(isSaveDisabled)
            }
        }
        .alert("放弃修改？", isPresented: $showsDiscardAlert) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃", role: .destructive) { dismiss() }
        } message: {
            Text("你有未保存的修改，确定要放弃吗？")
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                viewModel.receiveSelectedPhotoData(data)
                selectedPhotoItem = nil
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { viewModel.pendingCropImage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelCropping()
                    }
                }
            )
        ) {
            if let image = viewModel.pendingCropImage {
                AvatarCropperView(
                    image: image,
                    onCancel: {
                        viewModel.cancelCropping()
                    },
                    onComplete: { croppedImage in
                        viewModel.applyCroppedImage(croppedImage)
                    }
                )
            }
        }
        .onAppear {
            editableSpaceName = spaceName
        }
    }

    // MARK: - Sections

    /// 双人头像区域：左侧自己（可编辑），右侧对方（只读）
    private var avatarPairSection: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                // 自己的头像（可编辑）
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        UserAvatarView(
                            avatarAsset: viewModel.previewAvatarAsset,
                            displayName: viewModel.displayName,
                            size: 96,
                            fillColor: AppTheme.colors.avatarWarm,
                            symbolColor: AppTheme.colors.title.opacity(0.82),
                            symbolFont: AppTheme.typography.sized(28, weight: .semibold),
                            overrideImage: viewModel.previewUIImage
                        )
                        .shadow(color: AppTheme.colors.shadow.opacity(0.18), radius: 8, y: 4)

                        // 编辑徽章
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(AppTheme.colors.coral)
                            .background(Circle().fill(AppTheme.colors.surfaceElevated).frame(width: 22, height: 22))
                    }

                    Text("我")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.6))
                }

                Text("&")
                    .font(AppTheme.typography.sized(18, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.3))

                // 对方的头像（只读）
                VStack(spacing: 8) {
                    UserAvatarView(
                        avatarAsset: partnerAvatar.avatarAsset,
                        displayName: partnerAvatar.displayName,
                        size: 96,
                        fillColor: AppTheme.colors.avatarNeutral,
                        symbolColor: AppTheme.colors.title.opacity(0.82),
                        symbolFont: AppTheme.typography.sized(28, weight: .semibold),
                        overrideImage: nil
                    )
                    .shadow(color: AppTheme.colors.shadow.opacity(0.12), radius: 6, y: 3)
                    .opacity(0.8)

                    Text("TA")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)

            // 头像操作按钮
            HStack(spacing: 16) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("更换头像", systemImage: "photo")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.coral)
                }

                if viewModel.canRemovePhoto {
                    Button {
                        viewModel.removePhoto()
                    } label: {
                        Label("移除照片", systemImage: "xmark.circle")
                            .font(AppTheme.typography.sized(13, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("我的昵称")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.7))

            TextField("输入你的名字", text: $viewModel.displayName)
                .font(AppTheme.typography.sized(16, weight: .medium))
                .textFieldStyle(.roundedBorder)

            if let message = viewModel.nameValidationMessage {
                Text(message)
                    .font(AppTheme.typography.sized(12, weight: .medium))
                    .foregroundStyle(AppTheme.colors.coral)
            }

            HStack(spacing: 8) {
                Text("对方昵称")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.7))
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.3))
            }
            .padding(.top, AppTheme.spacing.md)

            Text(partnerName)
                .font(AppTheme.typography.sized(16, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.colors.background.opacity(0.6))
                )
        }
    }

    private var spaceNameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("共享空间名称")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.7))

            TextField("一起的任务空间", text: $editableSpaceName)
                .font(AppTheme.typography.sized(16, weight: .medium))
                .textFieldStyle(.roundedBorder)

            Text("为你们的共享空间取一个名字吧")
                .font(AppTheme.typography.sized(12, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.4))
        }
    }

    // MARK: - Helpers

    private var isSaveDisabled: Bool {
        let spaceNameChanged = editableSpaceName.trimmingCharacters(in: .whitespacesAndNewlines) != spaceName
        if spaceNameChanged {
            return false // 空间名改了就可以保存
        }
        return viewModel.isSaveDisabled
    }

    private func handleDismissTapped() {
        let spaceNameChanged = editableSpaceName.trimmingCharacters(in: .whitespacesAndNewlines) != spaceName
        if viewModel.hasUnsavedChanges || spaceNameChanged {
            showsDiscardAlert = true
        } else {
            dismiss()
        }
    }
}
