import Photos
import PhotosUI
import SwiftUI
import UIKit

struct OCRPhotoLibraryGridPanel: View {
    let onBack: () -> Void
    let onImageSelected: (UIImage) -> Void

    @State private var authorizationState: OCRPhotoAuthorizationState = .checking
    @State private var assets: [PHAsset] = []
    @State private var isLoadingSelection = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
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
                        .padding(.bottom, 112)
                    }
                }
            }

            VStack {
                Spacer(minLength: 0)
                photoControls
            }
            .safeAreaPadding(.horizontal, AppTheme.spacing.xl)
            .safeAreaPadding(.bottom, AppTheme.spacing.xl)

            if isLoadingSelection {
                OCRMediaLoadingView(title: "正在载入图片")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task {
            await requestAccessAndLoad()
        }
    }

    private var photoControls: some View {
        HStack(alignment: .bottom, spacing: AppTheme.spacing.md) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.36), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(authorizationState == .limited ? "管理照片" : "全部照片") {
                if authorizationState == .limited || authorizationState == .authorized {
                    presentLimitedLibraryPicker()
                }
            }
            .font(AppTheme.typography.textStyle(.title3, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.42), radius: 8, x: 0, y: 2)
            .buttonStyle(.plain)
            .disabled(authorizationState == .checking || authorizationState == .denied)

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, AppTheme.spacing.md)
                    .padding(.vertical, AppTheme.spacing.xs)
                    .shadow(color: .black.opacity(0.42), radius: 6, x: 0, y: 2)
            }
        }
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

private enum OCRPhotoAuthorizationState {
    case checking
    case authorized
    case limited
    case denied
}

private struct OCRPhotoAssetThumbnail: View {
    let asset: PHAsset
    let onSelect: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onSelect) {
            ZStack {
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
            .buttonStyle(.plain)
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
