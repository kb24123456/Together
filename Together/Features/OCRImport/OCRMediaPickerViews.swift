import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

struct OCRCameraCapturePanel: View {
    let onBack: () -> Void
    let onImageCaptured: (UIImage) -> Void

    @State private var controller = OCRCameraController()
    @State private var authorizationState: OCRCameraAuthorizationState = .checking
    @State private var isCapturing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            switch authorizationState {
            case .checking:
                OCRMediaLoadingView(title: "正在准备相机")
            case .denied:
                OCRMediaPermissionView(
                    systemImage: "camera",
                    title: "无法使用相机",
                    message: "请在系统设置中允许 Together 使用相机。"
                )
            case .unavailable:
                OCRMediaPermissionView(
                    systemImage: "camera.slash",
                    title: "当前设备不支持拍照",
                    message: "可以从照片中选择纸面清单继续导入。"
                )
            case .authorized:
                cameraContent
            }
        }
        .task {
            await prepareCamera()
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var cameraContent: some View {
        ZStack(alignment: .bottom) {
            OCRCameraPreview(session: controller.session)
                .clipShape(.rect(cornerRadius: 34, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                }
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.bottom, AppTheme.spacing.md)

            VStack(spacing: AppTheme.spacing.md) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.spacing.md)
                        .padding(.vertical, AppTheme.spacing.xs)
                        .background(.black.opacity(0.42), in: Capsule(style: .continuous))
                }

                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(AppTheme.typography.sized(20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.black.opacity(0.42), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 70, height: 70)
                            Circle()
                                .stroke(.white.opacity(0.72), lineWidth: 5)
                                .frame(width: 82, height: 82)
                            if isCapturing {
                                ProgressView()
                                    .tint(.black)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCapturing)

                    Spacer()

                    Circle()
                        .fill(.black.opacity(0.42))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Image(systemName: "doc.text.viewfinder")
                                .font(AppTheme.typography.sized(20, weight: .bold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.bottom, AppTheme.spacing.xl)
            }
        }
    }

    private func prepareCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            authorizationState = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
            controller.configureAndStart { message in
                errorMessage = message
            }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationState = granted ? .authorized : .denied
            if granted {
                controller.configureAndStart { message in
                    errorMessage = message
                }
            }
        case .denied, .restricted:
            authorizationState = .denied
        @unknown default:
            authorizationState = .denied
        }
    }

    private func capturePhoto() {
        isCapturing = true
        errorMessage = nil
        controller.capturePhoto { result in
            isCapturing = false
            switch result {
            case .success(let image):
                onImageCaptured(image)
            case .failure(let error):
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct OCRPhotoLibraryGridPanel: View {
    let onBack: () -> Void
    let onImageSelected: (UIImage) -> Void

    @State private var authorizationState: OCRPhotoAuthorizationState = .checking
    @State private var assets: [PHAsset] = []
    @State private var isLoadingSelection = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            photoToolbar

            ZStack {
                switch authorizationState {
                case .checking:
                    OCRMediaLoadingView(title: "正在读取照片")
                case .denied:
                    OCRMediaPermissionView(
                        systemImage: "photo.on.rectangle.angled",
                        title: "无法读取照片",
                        message: "请在系统设置中允许 Together 读取照片，或返回使用相机拍摄。"
                    )
                case .authorized, .limited:
                    if assets.isEmpty {
                        OCRMediaPermissionView(
                            systemImage: "photo.stack",
                            title: "没有可用照片",
                            message: "请选择更多照片权限，或返回使用相机拍摄。"
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(assets, id: \.localIdentifier) { asset in
                                    OCRPhotoAssetThumbnail(asset: asset) {
                                        select(asset)
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                }
                            }
                            .padding(.horizontal, AppTheme.spacing.lg)
                            .padding(.bottom, AppTheme.spacing.xl)
                        }
                    }
                }

                if isLoadingSelection {
                    OCRMediaLoadingView(title: "正在载入图片")
                        .background(.ultraThinMaterial)
                }
            }
        }
        .task {
            await requestAccessAndLoad()
        }
    }

    private var photoToolbar: some View {
        HStack(spacing: AppTheme.spacing.md) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(AppTheme.typography.sized(18, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.colors.surfaceElevated.opacity(0.82), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if authorizationState == .limited {
                Button("管理照片") {
                    presentLimitedLibraryPicker()
                }
                .buttonStyle(.bordered)
            }

            Button("全部照片") {
                presentLimitedLibraryPicker()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, AppTheme.spacing.lg)
        .padding(.bottom, AppTheme.spacing.md)
    }

    private func requestAccessAndLoad() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let resolvedStatus: PHAuthorizationStatus
        if status == .notDetermined {
            resolvedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            resolvedStatus = status
        }

        switch resolvedStatus {
        case .authorized:
            authorizationState = .authorized
            loadRecentAssets()
        case .limited:
            authorizationState = .limited
            loadRecentAssets()
        case .denied, .restricted:
            authorizationState = .denied
        case .notDetermined:
            authorizationState = .checking
        @unknown default:
            authorizationState = .denied
        }
    }

    private func loadRecentAssets() {
        let options = PHFetchOptions()
        options.fetchLimit = 90
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var fetchedAssets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        assets = fetchedAssets
    }

    private func select(_ asset: PHAsset) {
        isLoadingSelection = true
        errorMessage = nil
        Task {
            do {
                let image = try await OCRPhotoLibraryImageLoader.image(for: asset)
                isLoadingSelection = false
                onImageSelected(image)
            } catch {
                isLoadingSelection = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func presentLimitedLibraryPicker() {
        guard let viewController = UIApplication.shared.ocrTopViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
        loadRecentAssets()
    }
}

private enum OCRCameraAuthorizationState {
    case checking
    case authorized
    case denied
    case unavailable
}

private enum OCRPhotoAuthorizationState {
    case checking
    case authorized
    case limited
    case denied
}

private struct OCRCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

nonisolated final class OCRCameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "together.ocr.camera.session")
    private var isConfigured = false
    private var captureCompletion: ((Result<UIImage, Error>) -> Void)?

    func configureAndStart(onError: @escaping (String) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.isConfigured == false {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    DispatchQueue.main.async {
                        onError(error.localizedDescription)
                    }
                    return
                }
            }

            if self.session.isRunning == false {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (Result<UIImage, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureCompletion = completion
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else {
            throw OCRCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw OCRCameraError.cannotAddInput
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw OCRCameraError.cannotAddOutput
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            complete(.failure(error))
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            complete(.failure(OCRCameraError.invalidPhotoData))
            return
        }

        complete(.success(image))
    }

    private func complete(_ result: Result<UIImage, Error>) {
        let completion = captureCompletion
        captureCompletion = nil
        DispatchQueue.main.async {
            completion?(result)
        }
    }
}

private enum OCRCameraError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case invalidPhotoData

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "没有找到可用相机。"
        case .cannotAddInput:
            return "无法连接相机输入。"
        case .cannotAddOutput:
            return "无法准备拍照输出。"
        case .invalidPhotoData:
            return "无法读取拍摄的图片。"
        }
    }
}

private struct OCRPhotoAssetThumbnail: View {
    let asset: PHAsset
    let onSelect: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Rectangle()
                    .fill(AppTheme.colors.surfaceElevated)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            thumbnail = await OCRPhotoLibraryImageLoader.thumbnail(for: asset, size: CGSize(width: 260, height: 260))
        }
    }
}

private enum OCRPhotoLibraryImageLoader {
    static func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHCachingImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard didResume == false else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    static func image(for asset: PHAsset) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let image = UIImage(data: data) else {
                    continuation.resume(throwing: OCRPhotoLibraryError.invalidImageData)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}

private enum OCRPhotoLibraryError: LocalizedError {
    case invalidImageData

    var errorDescription: String? {
        "无法读取所选照片。"
    }
}

private struct OCRMediaLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: AppTheme.spacing.md) {
            ProgressView()
            Text(title)
                .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OCRMediaPermissionView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AppTheme.spacing.md) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(32, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.42))

            Text(title)
                .font(AppTheme.typography.textStyle(.title3, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)

            Text(message)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("打开设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.spacing.xl)
    }
}

private extension UIApplication {
    var ocrTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topPresentedViewController
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        presentedViewController?.topPresentedViewController ?? self
    }
}
