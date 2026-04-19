import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct EditProfileView: View {
    @State var viewModel: EditProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showsDiscardAlert = false
    @State private var cameraCaptureToken = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xl) {
                avatarSection
                nameSection
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.xxl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle(viewModel.navigationTitle)
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
                        let didSave = await viewModel.save()
                        if didSave {
                            HomeInteractionFeedback.completion()
                            dismiss()
                        }
                    }
                }
                .disabled(viewModel.isSaveDisabled)
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
            isPresented: $viewModel.showsErrorAlert
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
            isPresented: $viewModel.showsCropper,
            onDismiss: {
                viewModel.cancelCropping()
            }
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
    }

    private var albumButtonTitle: String {
        "相册选择"
    }

    private var avatarSection: some View {
        VStack(spacing: AppTheme.spacing.md) {
            ZStack {
                Circle()
                    .fill(AppTheme.colors.surfaceElevated)
                    .frame(width: 128, height: 128)

                avatarPreview
            }
            .shadow(color: AppTheme.colors.shadow.opacity(0.14), radius: 14, y: 6)

            HStack(spacing: AppTheme.spacing.md) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text(albumButtonTitle)
                        .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing.md)
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
                .padding(.vertical, AppTheme.spacing.md)
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
                .background(AppTheme.colors.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous))
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
    private var avatarPreview: some View {
        #if canImport(UIKit)
        if let image = viewModel.previewUIImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 116, height: 116)
                .clipShape(Circle())
        } else {
            UserAvatarView(
                avatarAsset: viewModel.previewAvatarAsset,
                displayName: viewModel.displayName,
                size: 116,
                fillColor: AppTheme.colors.avatarWarm,
                symbolColor: AppTheme.colors.title.opacity(0.82),
                symbolFont: AppTheme.typography.sized(40, weight: .semibold)
            )
        }
        #else
        UserAvatarView(
            avatarAsset: viewModel.previewAvatarAsset,
            displayName: viewModel.displayName,
            size: 116,
            fillColor: AppTheme.colors.avatarWarm,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(40, weight: .semibold)
        )
        #endif
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("名称")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)

            TextField("输入你的名称", text: $viewModel.displayName)
                .font(AppTheme.typography.textStyle(.title3, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.horizontal, AppTheme.spacing.md)
                .padding(.vertical, AppTheme.spacing.md)
                .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radius.xl, style: .continuous))

            if let validationMessage = viewModel.nameValidationMessage {
                Text(validationMessage)
                    .font(AppTheme.typography.textStyle(.footnote))
                    .foregroundStyle(viewModel.isNameValid ? AppTheme.colors.body : AppTheme.colors.danger)
            } else {
                Text("最多 20 个字符")
                    .font(AppTheme.typography.textStyle(.footnote))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.7))
            }
        }
    }

    private func handleDismissTapped() {
        if viewModel.hasUnsavedChanges {
            showsDiscardAlert = true
        } else {
            dismiss()
        }
    }
}

#if canImport(UIKit)
struct AvatarCropperView: View {
    private struct CropLayout {
        let cropDiameter: CGFloat
        let baseScale: CGFloat
        let effectiveScale: CGFloat
        let clampedOffset: CGSize
        let renderedWidth: CGFloat
        let renderedHeight: CGFloat
    }

    let image: UIImage
    let onCancel: () -> Void
    let onComplete: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var workingImage: UIImage
    @State private var committedScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    init(
        image: UIImage,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (UIImage) -> Void
    ) {
        self.image = image
        self.onCancel = onCancel
        self.onComplete = onComplete
        _workingImage = State(initialValue: image)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropDiameter = resolvedCropDiameter(for: proxy.size)
                let layout = makeLayout(cropDiameter: cropDiameter)

                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    cropCanvas(layout: layout)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    cropActionBar(layout: layout)
                        .padding(.horizontal, AppTheme.spacing.lg)
                        .padding(.top, AppTheme.spacing.md)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, AppTheme.spacing.md))
                        .background(Color.black.opacity(0.001))
                }
            }
            .navigationTitle("裁剪头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        HomeInteractionFeedback.selection()
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
        }
        .tint(.white)
        .presentationBackground(.clear)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if
                    let data = try? await item.loadTransferable(type: Data.self),
                    let updatedImage = UIImage(data: data)?.normalizedOrientationImage()
                {
                    workingImage = updatedImage
                    committedScale = 1
                    gestureScale = 1
                    committedOffset = .zero
                    gestureOffset = .zero
                }
                selectedPhotoItem = nil
            }
        }
    }

    private func resolvedCropDiameter(for availableSize: CGSize) -> CGFloat {
        let availableWidth = availableSize.width.isFinite && availableSize.width > 0 ? availableSize.width : 328
        return min(max(availableWidth - 48, 240), 320)
    }

    private func makeLayout(cropDiameter: CGFloat) -> CropLayout {
        let imageSize = workingImage.size
        let baseScale = max(cropDiameter / imageSize.width, cropDiameter / imageSize.height)
        let effectiveScale = min(max(committedScale * gestureScale, 1), 4)
        let clampedOffset = clampOffset(
            CGSize(
                width: committedOffset.width + gestureOffset.width,
                height: committedOffset.height + gestureOffset.height
            ),
            imageSize: imageSize,
            cropDiameter: cropDiameter,
            baseScale: baseScale,
            effectiveScale: effectiveScale
        )

        return CropLayout(
            cropDiameter: cropDiameter,
            baseScale: baseScale,
            effectiveScale: effectiveScale,
            clampedOffset: clampedOffset,
            renderedWidth: imageSize.width * baseScale * effectiveScale,
            renderedHeight: imageSize.height * baseScale * effectiveScale
        )
    }

    private func cropCanvas(layout: CropLayout) -> some View {
        GeometryReader { proxy in
            ZStack {
                Image(uiImage: workingImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: layout.renderedWidth, height: layout.renderedHeight)
                    .offset(layout.clampedOffset)
                    .gesture(cropGesture(cropDiameter: layout.cropDiameter))

                cropOverlay(cropDiameter: layout.cropDiameter)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func cropActionBar(layout: CropLayout) -> some View {
        HStack(spacing: AppTheme.spacing.md) {
            Button("取消") {
                HomeInteractionFeedback.selection()
                onCancel()
                dismiss()
            }
            .frame(maxWidth: .infinity)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("重新选择")
                    .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    HomeInteractionFeedback.selection()
                }
            )

            Button("完成") {
                if let croppedImage = makeCroppedImage(
                    cropDiameter: layout.cropDiameter,
                    baseScale: layout.baseScale,
                    effectiveScale: layout.effectiveScale,
                    clampedOffset: layout.clampedOffset
                ) {
                    HomeInteractionFeedback.completion()
                    onComplete(croppedImage)
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .font(AppTheme.typography.textStyle(.body, weight: .semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, AppTheme.spacing.md)
        .padding(.vertical, AppTheme.spacing.md)
        .background(AppTheme.colors.glassTint, in: RoundedRectangle(cornerRadius: AppTheme.radius.xl, style: .continuous))
    }

    private func cropGesture(cropDiameter: CGFloat) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    gestureOffset = value.translation
                }
                .onEnded { value in
                    let baseScale = max(cropDiameter / workingImage.size.width, cropDiameter / workingImage.size.height)
                    let effectiveScale = min(max(committedScale * gestureScale, 1), 4)
                    committedOffset = clampOffset(
                        CGSize(
                            width: committedOffset.width + value.translation.width,
                            height: committedOffset.height + value.translation.height
                        ),
                        imageSize: workingImage.size,
                        cropDiameter: cropDiameter,
                        baseScale: baseScale,
                        effectiveScale: effectiveScale
                    )
                    gestureOffset = .zero
                },
            MagnifyGesture()
                .onChanged { value in
                    gestureScale = value.magnification
                }
                .onEnded { value in
                    committedScale = min(max(committedScale * value.magnification, 1), 4)
                    gestureScale = 1
                    let baseScale = max(cropDiameter / workingImage.size.width, cropDiameter / workingImage.size.height)
                    committedOffset = clampOffset(
                        committedOffset,
                        imageSize: workingImage.size,
                        cropDiameter: cropDiameter,
                        baseScale: baseScale,
                        effectiveScale: committedScale
                    )
                }
        )
    }

    private func cropOverlay(cropDiameter: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.42))
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: cropDiameter, height: cropDiameter)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }

            Circle()
                .stroke(Color.white.opacity(0.94), lineWidth: 2)
                .frame(width: cropDiameter, height: cropDiameter)
        }
    }

    private func clampOffset(
        _ proposedOffset: CGSize,
        imageSize: CGSize,
        cropDiameter: CGFloat,
        baseScale: CGFloat,
        effectiveScale: CGFloat
    ) -> CGSize {
        let renderedWidth = imageSize.width * baseScale * effectiveScale
        let renderedHeight = imageSize.height * baseScale * effectiveScale
        let maxX = max((renderedWidth - cropDiameter) / 2, 0)
        let maxY = max((renderedHeight - cropDiameter) / 2, 0)

        return CGSize(
            width: min(max(proposedOffset.width, -maxX), maxX),
            height: min(max(proposedOffset.height, -maxY), maxY)
        )
    }

    private func makeCroppedImage(
        cropDiameter: CGFloat,
        baseScale: CGFloat,
        effectiveScale: CGFloat,
        clampedOffset: CGSize
    ) -> UIImage? {
        let totalScale = baseScale * effectiveScale
        let visibleWidth = cropDiameter / totalScale
        let visibleHeight = cropDiameter / totalScale

        let originX = ((workingImage.size.width - visibleWidth) / 2) - (clampedOffset.width / totalScale)
        let originY = ((workingImage.size.height - visibleHeight) / 2) - (clampedOffset.height / totalScale)
        let cropRectInPoints = CGRect(
            x: max(0, min(originX, workingImage.size.width - visibleWidth)),
            y: max(0, min(originY, workingImage.size.height - visibleHeight)),
            width: min(visibleWidth, workingImage.size.width),
            height: min(visibleHeight, workingImage.size.height)
        )

        let pixelRect = CGRect(
            x: cropRectInPoints.origin.x * workingImage.scale,
            y: cropRectInPoints.origin.y * workingImage.scale,
            width: cropRectInPoints.size.width * workingImage.scale,
            height: cropRectInPoints.size.height * workingImage.scale
        ).integral

        guard let cgImage = workingImage.cgImage?.cropping(to: pixelRect) else { return nil }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        return renderer.image { _ in
            UIImage(cgImage: cgImage, scale: workingImage.scale, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let token: UUID
    let onCapture: (UIImage?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        picker.overrideUserInterfaceStyle = .dark
        picker.view.backgroundColor = .black
        picker.view.clipsToBounds = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        _ = token
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage?) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage?) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage)?.normalizedOrientationImage()
            onCapture(image)
        }
    }
}
#endif

#Preview("Edit Profile") {
    let context = AppContext.makeBootstrappedContext()
    NavigationStack {
        EditProfileView(
            viewModel: context.profileViewModel.makeEditProfileViewModel(
                user: context.sessionStore.currentUser
            )
        )
    }
}
