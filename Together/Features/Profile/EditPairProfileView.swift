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
        .alert("放弃未保存的修改？", isPresented: $showsDiscardAlert) {
            Button("继续编辑", role: .cancel) {
                HomeInteractionFeedback.selection()
            }
            Button("放弃修改", role: .destructive) {
                HomeInteractionFeedback.selection()
                dismiss()
            }
        } message: {
            Text("你对头像或名称的修改尚未保存。")
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearError()
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                HomeInteractionFeedback.selection()
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
        .fullScreenCover(isPresented: $viewModel.showsCameraPicker) {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                CameraCaptureView(
                    token: cameraCaptureToken,
                    onCapture: { image in
                        viewModel.receiveCapturedPhoto(image)
                    },
                    onCancel: {
                        viewModel.showsCameraPicker = false
                    }
                )
                .ignoresSafeArea()
                .background(Color.black)
            }
            .background(Color.black)
            .ignoresSafeArea()
        }
        .onAppear {
            editableSpaceName = spaceName
        }
    }

    // MARK: - Sections

    /// 双人头像区域：左侧自己（可编辑），右侧对方（只读）
    private var avatarPairSection: some View {
        VStack(spacing: AppTheme.spacing.md) {
            HStack(alignment: .center, spacing: 24) {
                // 自己的头像（可编辑）
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.colors.surfaceElevated)
                            .frame(width: 116, height: 116)

                        myAvatarPreview
                    }
                    .shadow(color: AppTheme.colors.shadow.opacity(0.14), radius: 14, y: 6)

                    Text("我")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.6))
                }

                Text("&")
                    .font(AppTheme.typography.sized(18, weight: .bold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.3))

                // 对方的头像（只读）
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.colors.surfaceElevated)
                            .frame(width: 116, height: 116)

                        UserAvatarView(
                            avatarAsset: partnerAvatar.avatarAsset,
                            displayName: partnerAvatar.displayName,
                            size: 104,
                            fillColor: AppTheme.colors.avatarNeutral,
                            symbolColor: AppTheme.colors.title.opacity(0.82),
                            symbolFont: AppTheme.typography.sized(36, weight: .semibold),
                            overrideImage: nil
                        )
                    }
                    .shadow(color: AppTheme.colors.shadow.opacity(0.12), radius: 14, y: 6)
                    .opacity(0.8)

                    Text("TA")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)

            // 头像操作按钮（与单人模式一致的 capsule 样式）
            HStack(spacing: AppTheme.spacing.md) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("相册选择")
                        .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.colors.surfaceElevated, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        HomeInteractionFeedback.selection()
                    }
                )

                Button("拍照") {
                    HomeInteractionFeedback.selection()
                    cameraCaptureToken = UUID()
                    Task {
                        await viewModel.handleCameraTapped()
                    }
                }
                .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.colors.surfaceElevated, in: Capsule(style: .continuous))
            }

            if let cameraErrorMessage = viewModel.cameraErrorMessage {
                HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                    Text(cameraErrorMessage)
                        .font(AppTheme.typography.textStyle(.footnote))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.shouldShowCameraSettingsAction {
                        Button("去设置") {
                            HomeInteractionFeedback.selection()
                            viewModel.openSystemSettings()
                        }
                        .font(AppTheme.typography.textStyle(.footnote, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                    } else {
                        Button("知道了") {
                            HomeInteractionFeedback.selection()
                            viewModel.clearCameraError()
                        }
                        .font(AppTheme.typography.textStyle(.footnote, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                    }
                }
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.sm)
                .background(AppTheme.colors.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if viewModel.canRemovePhoto {
                Button {
                    HomeInteractionFeedback.selection()
                    viewModel.removePhoto()
                } label: {
                    Text("移除照片")
                        .font(AppTheme.typography.textStyle(.body, weight: .medium))
                        .foregroundStyle(AppTheme.colors.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacing.md)
    }

    @ViewBuilder
    private var myAvatarPreview: some View {
        #if canImport(UIKit)
        if let image = viewModel.previewUIImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
        } else {
            UserAvatarView(
                avatarAsset: viewModel.previewAvatarAsset,
                displayName: viewModel.displayName,
                size: 104,
                fillColor: AppTheme.colors.avatarWarm,
                symbolColor: AppTheme.colors.title.opacity(0.82),
                symbolFont: AppTheme.typography.sized(36, weight: .semibold)
            )
        }
        #else
        UserAvatarView(
            avatarAsset: viewModel.previewAvatarAsset,
            displayName: viewModel.displayName,
            size: 104,
            fillColor: AppTheme.colors.avatarWarm,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(36, weight: .semibold)
        )
        #endif
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("我的昵称")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            TextField("输入你的名字", text: $viewModel.displayName)
                .font(AppTheme.typography.textStyle(.title3, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, 16)
                .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if let message = viewModel.nameValidationMessage {
                Text(message)
                    .font(AppTheme.typography.textStyle(.footnote))
                    .foregroundStyle(viewModel.isNameValid ? AppTheme.colors.body : AppTheme.colors.danger)
            } else {
                Text("最多 20 个字符")
                    .font(AppTheme.typography.textStyle(.footnote))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.7))
            }

            HStack(spacing: 8) {
                Text("对方昵称")
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.3))
            }
            .padding(.top, AppTheme.spacing.md)

            Text(partnerName)
                .font(AppTheme.typography.textStyle(.title3, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.5))
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.colors.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var spaceNameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("共享空间名称")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            TextField("一起的任务空间", text: $editableSpaceName)
                .font(AppTheme.typography.textStyle(.title3, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, 16)
                .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("为你们的共享空间取一个名字吧")
                .font(AppTheme.typography.textStyle(.footnote))
                .foregroundStyle(AppTheme.colors.body.opacity(0.7))
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
